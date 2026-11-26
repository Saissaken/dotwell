import AppKit
import MonitorCore
import MonitorUI

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
    private let settings = AppSettings()
    private lazy var sampler = Sampler(configuration: settings.configuration)
    private let updater = Updater()
    private lazy var settingsWindow = SettingsWindowController { [settings, updater] in
        let model = SettingsModel(
            settings: settings, launchAtLogin: LoginItem.isEnabled, updates: updater.makeSettings())
        model.setLaunchAtLogin = { enabled in
            LoginItem.setEnabled(enabled)
            return LoginItem.isEnabled
        }
        return model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMover.moveIfNeeded() { return }  // relaunching from the Applications folder
        AppMover.offerInstallerCleanup()
        NSApp.mainMenu = MainMenu.make(openSettings: #selector(openSettings(_:)), target: self)
        let sampler = self.sampler
        settings.onConfigurationChange = { sampler.apply($0) }
        statusController = StatusItemController(sampler: sampler, settings: settings, updater: updater) {
            [weak self] page in self?.settingsWindow.show(page: page)
        }
        LoginItem.registerOnFirstLaunch()
        observeSleep()
        sampler.start()
    }

    @objc func openSettings(_ sender: Any?) {
        settingsWindow.show()
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
