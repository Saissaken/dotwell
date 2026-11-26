import AppKit
import MonitorCore

@main
enum MonitorMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private let sampler = Sampler()
    private let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(sampler: sampler, updater: updater)
        LoginItem.registerOnFirstLaunch()
        observeSleep()
        sampler.start()
    }

    /// Pause all sampling while the Mac or its displays sleep.
    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        let sampler = self.sampler
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in sampler.stop() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in sampler.start() }
        }
    }
}
