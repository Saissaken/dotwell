import AppKit
import MonitorUI

/// The Settings window: toolbar tabs like Safari's or Xcode's settings, one SwiftUI view per tab.
///
/// Like the popover, the window and its views exist only while it is open. While it is open the app
/// shows in the Dock and the app switcher, so the window can be found again like any other.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let makeModel: () -> SettingsModel
    private static let selectedTabKey = "settingsSelectedTab"

    init(makeModel: @escaping () -> SettingsModel) {
        self.makeModel = makeModel
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController(model: makeModel())
        let saved = UserDefaults.standard.integer(forKey: Self.selectedTabKey)
        tabs.selectedTabViewItemIndex = SettingsTab.allCases.indices.contains(saved) ? saved : 0
        tabs.onSelect = { index in UserDefaults.standard.set(index, forKey: Self.selectedTabKey) }
        let window = tabs.makeWindow()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("Settings")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
