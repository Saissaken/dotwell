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

    func testTopPicksTheLargestAndIgnoresIdleEntries() {
        let entries = [usage("A", cpu: 0.2), usage("B", cpu: 1.5), usage("C", cpu: 0), usage("D", cpu: 1.5)]
        XCTAssertEqual(ProcessProbe.top(entries, by: \.cpu, minimum: 0.001)?.name, "B", "ties break by name")
        XCTAssertNil(ProcessProbe.top([usage("C", cpu: 0)], by: \.cpu, minimum: 0.001))
    }

    func testSamplingTheTestRunnerFindsItself() throws {
        let probe = ProcessProbe()
        let me = ProcessProbe.group(pid: getpid()).id
        let first = probe.usage(now: DispatchTime.now().uptimeNanoseconds)
        XCTAssertFalse(first.hasRates, "rates need two samples")
        let mine = try XCTUnwrap(first.apps.first { $0.id == me }, "the test process is readable")
        XCTAssertGreaterThan(mine.memoryBytes, 1_000_000)

        // Burn a little CPU so the second sample has something to measure.
        var x = 0.0
        let end = Date().addingTimeInterval(0.2)
        while Date() < end { x += sin(x) + 1 }
        XCTAssertGreaterThan(x, 0)

        let second = probe.usage(now: DispatchTime.now().uptimeNanoseconds)
        XCTAssertTrue(second.hasRates)
        let now = try XCTUnwrap(second.apps.first { $0.id == me })
        XCTAssertGreaterThan(now.cpu, 0.1)
        XCTAssertLessThan(now.cpu, Float(ProcessInfo.processInfo.activeProcessorCount) + 0.5)
        XCTAssertGreaterThanOrEqual(now.watts, 0)
        print("ProcessProbe: test runner used \(now.cpu * 100) % CPU and \(now.watts) W")

        let top = probe.sample()
        XCTAssertTrue(top.hasRates)
        XCTAssertNotNil(top.memory)

        probe.reset()
        XCTAssertNil(probe.elapsed(now: 0))
    }

    private func usage(_ name: String, cpu: Float) -> ProcessUsage {
        ProcessUsage(id: name, name: name, path: nil, cpu: cpu, memoryBytes: 1)
    }
}
