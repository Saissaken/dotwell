import MonitorCore
import XCTest

@testable import MonitorUI

/// Quit and Force Quit, tried on real processes.
final class AppActionsTests: XCTestCase {
    func testQuitAsksTheProcessToStop() throws {
        let process = try sleeper()
        XCTAssertTrue(AppActions.quit(pid: process.processIdentifier))
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
        XCTAssertEqual(process.terminationStatus, SIGTERM, "a polite request, which the process may handle")
    }

    func testForceQuitStopsTheProcessRightAway() throws {
        let process = try sleeper()
        XCTAssertTrue(AppActions.forceQuit(pid: process.processIdentifier))
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
        XCTAssertEqual(process.terminationStatus, SIGKILL, "can't be caught or ignored")
    }

    func testNothingIsSentWithoutAProcessID() {
        XCTAssertFalse(AppActions.quit(pid: 0), "kill(0, …) would signal Dotwell's whole process group")
        XCTAssertFalse(AppActions.forceQuit(pid: 0))
        XCTAssertFalse(AppActions.forceQuit(pid: -1), "kill(-1, …) would signal every process of the user")
    }

    func testTheMenuHeaderNamesTheProcess() {
        let one = ProcessUsage(id: "/bin/zsh", name: "zsh", path: "/bin/zsh", pid: 42, processCount: 1)
        XCTAssertEqual(AppActions.header(one), "zsh · PID 42 · 1 process")
        var many = one
        many.processCount = 14
        XCTAssertEqual(AppActions.header(many), "zsh · PID 42 · 14 processes")
    }

    private func sleeper() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        addTeardownBlock { if process.isRunning { process.terminate() } }
        return process
    }
}
