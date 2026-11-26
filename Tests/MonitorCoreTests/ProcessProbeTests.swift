import XCTest

@testable import MonitorCore

final class ProcessProbeTests: XCTestCase {
    func testHelpersGroupUnderTheOutermostApp() {
        let helper =
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/"
            + "Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        let group = ProcessProbe.group(executablePath: helper)
        XCTAssertEqual(group.id, "/Applications/Google Chrome.app")
        XCTAssertEqual(group.name, "Google Chrome")
        XCTAssertEqual(group.path, "/Applications/Google Chrome.app")
    }

    func testStandaloneExecutablesUseTheirFileName() {
        let group = ProcessProbe.group(executablePath: "/usr/libexec/syspolicyd")
        XCTAssertEqual(group.name, "syspolicyd")
        XCTAssertEqual(group.path, "/usr/libexec/syspolicyd")
    }

    func testTopSortsDescendingAndDropsIdleEntries() {
        let entries = [
            usage("A", cpu: 0.2), usage("B", cpu: 1.5), usage("C", cpu: 0), usage("D", cpu: 0.2), usage("E", cpu: 0.9),
        ]
        let top = ProcessProbe.top(entries, limit: 3, by: \.cpu, minimum: 0.001)
        XCTAssertEqual(top.map(\.name), ["B", "E", "A"])
    }

    func testSamplingTheTestRunnerFindsItself() throws {
        let probe = ProcessProbe()
        let first = probe.sample(limit: 1000)
        XCTAssertTrue(first.byCPU.isEmpty, "CPU needs two samples")
        let me = ProcessProbe.group(pid: getpid()).id
        XCTAssertNotNil(first.byMemory.first { $0.id == me }, "the test process is readable")

        // Burn a little CPU so the second sample has something to rank.
        var x = 0.0
        let end = Date().addingTimeInterval(0.2)
        while Date() < end { x += sin(x) + 1 }
        XCTAssertGreaterThan(x, 0)

        let second = probe.sample(limit: 1000)
        let cpu = try XCTUnwrap(second.byCPU.first { $0.id == me }?.cpu)
        XCTAssertGreaterThan(cpu, 0.1)
        XCTAssertLessThan(cpu, Float(ProcessInfo.processInfo.activeProcessorCount) + 0.5)

        probe.reset()
        XCTAssertNil(probe.elapsed(now: 0))
    }

    private func usage(_ name: String, cpu: Float) -> ProcessUsage {
        ProcessUsage(id: name, name: name, path: nil, cpu: cpu, memoryBytes: 1)
    }
}
