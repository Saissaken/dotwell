import AppKit
import Combine
import MonitorUI

/// The Settings window: a sidebar with one page per card of the popover, like System Settings.
///
/// Like the popover, the window and its views exist only while it is open. While it is open the app
/// shows in the Dock and the app switcher, so the window can be found again like any other.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let makeModel: () -> SettingsModel
    private static let selectedPageKey = "settingsSelectedPage"
    private var observer: AnyCancellable?

    init(makeModel: @escaping () -> SettingsModel) {
        self.makeModel = makeModel
    }

    /// Shows the window, on `tab` when given (otherwise on the tab last used).
    func show(tab: SettingsTab? = nil) {
        if let tab, let index = SettingsTab.allCases.firstIndex(of: tab) {
            UserDefaults.standard.set(index, forKey: Self.selectedTabKey)
            (window?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = index
        }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let saved = UserDefaults.standard.string(forKey: Self.selectedPageKey).flatMap(SettingsPage.init(id:))
        let controller = SettingsSplitViewController(model: makeModel(), page: saved ?? .general)
        observer = controller.navigation.$page.dropFirst().sink { page in
            UserDefaults.standard.set(page.id, forKey: Self.selectedPageKey)
        }
        let window = controller.makeWindow()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
        observer = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
