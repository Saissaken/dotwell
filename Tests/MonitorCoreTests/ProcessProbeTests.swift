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

    func testOnlyTheBundlesOwnExecutableIsItsMainProcess() {
        XCTAssertTrue(ProcessProbe.group(executablePath: "/Applications/Arc.app/Contents/MacOS/Arc").isMain)
        let helper =
            "/Applications/Arc.app/Contents/Frameworks/ArcCore.framework/Helpers/"
            + "Browser Helper (Renderer).app/Contents/MacOS/Browser Helper (Renderer)"
        XCTAssertFalse(ProcessProbe.group(executablePath: helper).isMain)
        XCTAssertFalse(
            ProcessProbe.group(executablePath: "/Applications/Warp.app/Contents/MacOS/bin/stable").isMain,
            "a tool in a subfolder is not the app")
        XCTAssertFalse(
            ProcessProbe.group(executablePath: "/Applications/X.app/Contents/Resources/helper").isMain)
        XCTAssertFalse(ProcessProbe.group(executablePath: "/usr/libexec/sharingd").isMain)
    }

    func testTheMainExecutableLeadsThenTheOldestProcess() {
        typealias Leader = ProcessProbe.Leader
        let main = Leader(pid: 900, isMain: true, startTime: 50)
        let olderHelper = Leader(pid: 100, isMain: false, startTime: 10)
        XCTAssertTrue(main.leads(olderHelper), "the app's own process wins even if a helper is older")
        XCTAssertFalse(olderHelper.leads(main))
        let newerHelper = Leader(pid: 50, isMain: false, startTime: 20)
        XCTAssertTrue(olderHelper.leads(newerHelper), "start time decides, not the (reusable) pid number")
    }

    func testRankedListsTheLargestFirstAndIgnoresIdleEntries() {
        let entries = [
            usage("A", cpu: 0.2), usage("B", cpu: 1.5), usage("C", cpu: 0), usage("D", cpu: 1.5), usage("E", cpu: 0.4),
        ]
        let ranked = ProcessProbe.ranked(entries, by: \.cpu, minimum: 0.001, limit: 3)
        XCTAssertEqual(ranked.map(\.name), ["B", "D", "E"], "largest first, ties by name, at most the limit")
        let all = ProcessProbe.ranked(entries, by: \.cpu, minimum: 0.001, limit: 10)
        XCTAssertEqual(all.map(\.name), ["B", "D", "E", "A"])
        XCTAssertTrue(ProcessProbe.ranked([usage("C", cpu: 0)], by: \.cpu, minimum: 0.001, limit: 5).isEmpty)
    }

    /// Runs two copies of a uniquely named executable and checks they are counted as one entry
    /// whose pid is the first one started.
    func testProcessesOfOneExecutableAddUpUnderTheOldest() throws {
        let name = "dotwell-test-sleep-\(UUID().uuidString.prefix(8))"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let executable = dir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)

        func launch() throws -> Process {
            let process = Process()
            process.executableURL = executable
            process.arguments = ["30"]
            try process.run()
            return process
        }
        let first = try launch()
        Thread.sleep(forTimeInterval: 0.05)
        let second = try launch()
        defer {
            first.terminate()
            second.terminate()
        }
        Thread.sleep(forTimeInterval: 0.1)

        let apps = ProcessProbe().usage(now: DispatchTime.now().uptimeNanoseconds).apps
        let entry = try XCTUnwrap(apps.first { $0.name == name }, "both copies are readable")
        XCTAssertEqual(entry.processCount, 2)
        XCTAssertEqual(entry.pid, first.processIdentifier)
    }

    func testSamplingTheTestRunnerFindsItself() throws {
        let probe = ProcessProbe()
        let me = ProcessProbe.group(pid: getpid()).id
        let first = probe.usage(now: DispatchTime.now().uptimeNanoseconds)
        XCTAssertFalse(first.hasRates, "rates need two samples")
        let mine = try XCTUnwrap(first.apps.first { $0.id == me }, "the test process is readable")
        XCTAssertGreaterThan(mine.memoryBytes, 1_000_000)
        XCTAssertGreaterThanOrEqual(mine.processCount, 1)
        XCTAssertEqual(ProcessProbe.group(pid: mine.pid).id, me, "the entry's pid belongs to it")

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
        XCTAssertLessThanOrEqual(top.byMemory.count, TopApps.limit)
        XCTAssertEqual(top.byMemory, top.byMemory.sorted { $0.memoryBytes > $1.memoryBytes }, "largest first")

        probe.reset()
        XCTAssertNil(probe.elapsed(now: 0))
    }

    private func usage(_ name: String, cpu: Float) -> ProcessUsage {
        ProcessUsage(id: name, name: name, path: nil, cpu: cpu, memoryBytes: 1)
    }
}
