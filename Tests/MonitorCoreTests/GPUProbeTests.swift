import Foundation
import Metal
import XCTest

@testable import MonitorCore

final class GPUProbeTests: XCTestCase {
    // MARK: - Parsing

    func testUtilizationComesFromDeviceUtilization() throws {
        let statistics: [String: Any] = [
            "Device Utilization %": NSNumber(value: 39), "Renderer Utilization %": NSNumber(value: 35),
            "Tiler Utilization %": NSNumber(value: 12),
        ]
        XCTAssertEqual(try XCTUnwrap(GPUProbe.utilization(fromStatistics: statistics)), 0.39, accuracy: 0.0001)
        XCTAssertEqual(GPUProbe.utilization(fromStatistics: ["Device Utilization %": NSNumber(value: 140)]), 1)
        XCTAssertNil(GPUProbe.utilization(fromStatistics: ["Renderer Utilization %": NSNumber(value: 35)]))
    }

    func testCreatorNamesTheProcess() {
        XCTAssertEqual(GPUProbe.pid(fromCreator: "pid 4245, python3.12"), 4245)
        XCTAssertEqual(GPUProbe.pid(fromCreator: "pid 1, launchd"), 1)
        XCTAssertNil(GPUProbe.pid(fromCreator: "WindowServer"))
        XCTAssertNil(GPUProbe.pid(fromCreator: "pid , x"))
    }

    func testGPUTimeAddsUpEveryAPI() {
        let usage: [[String: Any]] = [
            ["API": "Metal", "accumulatedGPUTime": NSNumber(value: 1_500_000_000)],
            ["API": "GL", "accumulatedGPUTime": NSNumber(value: 500_000_000)],
        ]
        XCTAssertEqual(GPUProbe.gpuTime(fromAppUsage: usage), 2_000_000_000)
        XCTAssertEqual(GPUProbe.gpuTime(fromAppUsage: nil), 0)
        XCTAssertEqual(GPUProbe.gpuTime(fromAppUsage: "nonsense"), 0)
    }

    func testEnergyUnitsBecomeJoules() throws {
        XCTAssertEqual(try XCTUnwrap(GPUEnergyReader.joules(1_770, unit: "mJ")), 1.77, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(GPUEnergyReader.joules(1_770_000, unit: "uJ")), 1.77, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(GPUEnergyReader.joules(1_770_000_000, unit: "nJ")), 1.77, accuracy: 1e-9)
        XCTAssertNil(GPUEnergyReader.joules(5, unit: "W"))
        XCTAssertNil(GPUEnergyReader.joules(5, unit: nil))
        XCTAssertNil(GPUEnergyReader.joules(-5, unit: "mJ"))
        XCTAssertTrue(GPUEnergyReader.isGPUChannel("GPU Energy"))
        XCTAssertFalse(GPUEnergyReader.isGPUChannel("GPU SRAM Energy"))
    }

    func testGPUTemperatureUsesOnlyGPUSensors() {
        let readings: [(name: String, celsius: Double)] = [
            ("pACC MTR Temp Sensor0", 70), ("GPU MTR Temp Sensor1", 50), ("GPU MTR Temp Sensor4", 54),
            ("GPU MTR Temp Sensor5", 0),  // not plausible
        ]
        XCTAssertEqual(HIDThermalSensors.gpuTemperature(readings), 52)
        XCTAssertNil(HIDThermalSensors.gpuTemperature([("pACC MTR Temp Sensor0", 70)]))
        // The CPU reading never picks up a GPU sensor.
        XCTAssertEqual(HIDThermalSensors.cpuTemperature(readings), 70)
        XCTAssertNil(HIDThermalSensors.cpuTemperature([("GPU MTR Temp Sensor1", 50)]))
    }

    func testAppsGetTheirShareOfGPUTime() throws {
        let probe = ProcessProbe()
        let me = ProcessProbe.group(pid: getpid()).id
        let start: UInt64 = 1_000_000_000_000
        _ = probe.usage(now: start, gpuTimes: [getpid(): 7_000])
        // A quarter of a second of GPU time over one second.
        let second = probe.usage(now: start + 1_000_000_000, gpuTimes: [getpid(): 7_000 + 250_000_000])
        let mine = try XCTUnwrap(second.apps.first { $0.id == me })
        XCTAssertEqual(mine.gpu, 0.25, accuracy: 0.001)
        // A counter that went backwards (a reused pid) counts as nothing, not as a huge number.
        let third = probe.usage(now: start + 2_000_000_000, gpuTimes: [getpid(): 5])
        XCTAssertEqual(try XCTUnwrap(third.apps.first { $0.id == me }).gpu, 0)
    }

    // MARK: - Real readings

    /// Compares the probe with what `ioreg` prints for the same registry entry.
    func testReadingsMatchIoreg() throws {
        let probe = GPUProbe()
        guard probe.isAvailable else { throw XCTSkip("No Apple silicon GPU on this Mac") }
        let accelerator = try XCTUnwrap(try ioregAccelerators().first)
        print("GPUProbe: ioreg class \(accelerator["IOClass"] ?? "?"), cores \(accelerator["gpu-core-count"] ?? "?")")
        XCTAssertEqual(probe.coreCount, (accelerator["gpu-core-count"] as? NSNumber)?.intValue)

        guard let statistics = accelerator["PerformanceStatistics"] as? [String: Any],
            let expected = GPUProbe.utilization(fromStatistics: statistics)
        else { throw XCTSkip("This GPU publishes no utilization") }
        let reading = try XCTUnwrap(probe.utilization())
        print("GPUProbe: utilization \(reading), ioreg \(expected)")
        // Two reads a moment apart of a value that moves, so only a loose match.
        XCTAssertEqual(reading, expected, accuracy: 0.25)
    }

    /// Keeps the GPU busy from this process and checks that both the overall use and this app's share see it.
    func testAGPULoadShowsUp() throws {
        let probe = GPUProbe()
        guard probe.isAvailable, probe.utilization() != nil else { throw XCTSkip("No readable GPU on this Mac") }
        guard let load = try GPULoad() else { throw XCTSkip("No Metal device") }

        let processes = ProcessProbe()
        let me = ProcessProbe.group(pid: getpid()).id
        _ = processes.sample(gpuTimes: probe.processGPUTimes())
        _ = probe.watts()
        var peak: Float = 0
        let end = Date().addingTimeInterval(2)
        while Date() < end {
            load.run(milliseconds: 100)
            peak = max(peak, probe.utilization() ?? 0)
        }
        let watts = probe.watts()
        let times = probe.processGPUTimes()
        let usage = processes.usage(now: DispatchTime.now().uptimeNanoseconds, gpuTimes: times)
        let mine = usage.apps.first { $0.id == me }?.gpu
        let temperature = probe.temperature()
        print(
            "GPUProbe: peak utilization \(peak), this app \(String(describing: mine)),",
            "power \(String(describing: watts)) W, temperature \(String(describing: temperature)) °C")

        XCTAssertGreaterThan(peak, 0.2, "a busy GPU reads as busy")
        guard times[getpid()] != nil else {
            throw XCTSkip("This GPU driver does not account GPU time per app (virtual machine)")
        }
        let share = try XCTUnwrap(mine)
        XCTAssertGreaterThan(share, 0.1, "this app's GPU time is counted")
        XCTAssertLessThan(share, 1.5, "GPU time is in nanoseconds, not a larger unit")
        if let watts { XCTAssertGreaterThan(watts, 0) }
    }

    private func ioregAccelerators() throws -> [[String: Any]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-r", "-d", "1", "-c", "IOAccelerator", "-a"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]) ?? []
    }
}

/// A compute kernel that keeps the GPU busy.
private final class GPULoad {
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let buffer: MTLBuffer

    init?() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
            let buffer = device.makeBuffer(length: (1 << 20) * 4, options: .storageModePrivate)
        else { return nil }
        let source = """
            #include <metal_stdlib>
            using namespace metal;
            kernel void spin(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
                float x = float(id);
                for (int i = 0; i < 4000; i++) { x = fma(x, 1.0001f, 0.5f); x = sin(x); }
                out[id] = x;
            }
            """
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "spin") else { return nil }
        self.queue = queue
        self.buffer = buffer
        pipeline = try device.makeComputePipelineState(function: function)
    }

    func run(milliseconds: Int) {
        let end = Date().addingTimeInterval(Double(milliseconds) / 1000)
        while Date() < end {
            guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder()
            else { return }
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(buffer, offset: 0, index: 0)
            encoder.dispatchThreads(
                MTLSize(width: 1 << 20, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: pipeline.threadExecutionWidth, height: 1, depth: 1))
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
        }
    }
}
