import AppKit
import MonitorCore
import SwiftUI

/// What the top apps' context menu can do to an app: copy details, reveal it, or quit it.
/// Quitting acts on the entry's main process; for an app, macOS then closes its helpers too.
enum AppActions {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func showInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Asks the process to quit, like the Dock's Quit: an app may still ask to save documents.
    @discardableResult
    static func quit(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if let app = NSRunningApplication(processIdentifier: pid) { return app.terminate() }
        return kill(pid, SIGTERM) == 0
    }

    /// Stops the process right away; unsaved work is lost.
    @discardableResult
    static func forceQuit(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if let app = NSRunningApplication(processIdentifier: pid) { return app.forceTerminate() }
        return kill(pid, SIGKILL) == 0
    }

    /// Asks before force quitting, as the Force Quit Applications window does.
    @MainActor
    static func confirmForceQuit(_ name: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Force quit “\(name)”?"
        alert.informativeText = "You will lose any unsaved changes."
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func header(_ app: ProcessUsage) -> String {
        let processes = app.processCount == 1 ? "1 process" : "\(app.processCount) processes"
        return "\(app.name) · PID \(app.pid) · \(processes)"
    }
}

/// The right-click menu of an app in the top apps line and list.
struct AppContextMenu: View {
    var app: ProcessUsage
    /// Copies the PID; the list also shows a confirmation.
    var copyPID: () -> Void

    var body: some View {
        Text(AppActions.header(app))
        Button("Copy PID", action: copyPID)
        Button("Copy Path") {
            if let path = app.path { AppActions.copy(path) }
        }
        .disabled(app.path == nil)
        Button("Show in Finder") {
            if let path = app.path { AppActions.showInFinder(path) }
        }
        .disabled(!(app.path?.hasPrefix("/") ?? false))
        Divider()
        Button("Quit \(app.name)") { AppActions.quit(pid: app.pid) }
        Button("Force Quit \(app.name)…") {
            if AppActions.confirmForceQuit(app.name) { AppActions.forceQuit(pid: app.pid) }
        }
    }
}
