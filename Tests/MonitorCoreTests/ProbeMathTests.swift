import XCTest
@testable import MonitorCore

final class ProbeMathTests: XCTestCase {
    func testCPUUsage() {
        let a = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let b = CPUTicks(user: 130, system: 60, idle: 850, nice: 60)
        // busy = 30+10+10 = 50, total = 100
        XCTAssertEqual(CPUTicks.usage(from: a, to: b), 0.5, accuracy: 0.0001)
    }

    func testCPUUsageCounterWrap() {
        let a = CPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)
        let b = CPUTicks(user: 10, system: 0, idle: 20, nice: 0)
        // busy = 20 (wrapped), idle = 20
        XCTAssertEqual(CPUTicks.usage(from: a, to: b), 0.5, accuracy: 0.0001)
    }

    func testCPUUsageNoTime() {
        let a = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        XCTAssertEqual(CPUTicks.usage(from: a, to: a), 0)
    }

    func testNetworkRates() {
        let a = NetworkCounters(received: 1_000, sent: 500)
        let b = NetworkCounters(received: 2_000, sent: 1_500)
        let r = NetworkCounters.rates(from: a, to: b, seconds: 2)
        XCTAssertEqual(r.down, 4_000) // 1000 bytes * 8 / 2 s
        XCTAssertEqual(r.up, 4_000)
    }

    func testNetworkRatesCounterReset() {
        let r = NetworkCounters.rates(from: NetworkCounters(received: 5_000, sent: 5_000),
                                      to: NetworkCounters(received: 10, sent: 10), seconds: 1)
        XCTAssertEqual(r.down, 0)
        XCTAssertEqual(r.up, 0)
    }

    func testWatts() {
        XCTAssertEqual(PowerProbe.watts(millivolts: 12_000, milliamps: -1_500), 18, accuracy: 0.0001)
    }

    /// Smoke test: real probes return sane values on the CI Mac.
    func testLiveProbes() {
        let cpu = CPUProbe()
        _ = cpu.sample()
        usleep(100_000)
        if let usage = cpu.sample() { XCTAssert((0...1).contains(usage)) }

        let mem = MemoryProbe().sample()
        XCTAssertNotNil(mem)
        if let mem { XCTAssertGreaterThan(mem.totalBytes, 0); XCTAssertLessThanOrEqual(mem.usedBytes, mem.totalBytes) }

        XCTAssertNotNil(NetworkProbe().sample())
        let space = DiskProbe().space()
        XCTAssertNotNil(space)
        if let space { XCTAssertLessThanOrEqual(space.availableBytes, space.totalBytes) }
        _ = DiskProbe().ioCounters()
        _ = PowerProbe().sample() // CI runners have no battery; must not crash
    }
}
