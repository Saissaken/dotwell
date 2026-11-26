import AppKit
import SwiftUI

/// Toolbar tabs, like Safari's or Xcode's settings, with one SwiftUI view per tab.
/// The window title follows the selected tab.
public final class SettingsTabViewController: NSTabViewController {
    /// Called with the index of the tab the person picks.
    public var onSelect: ((Int) -> Void)?

    public init(model: SettingsModel) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsView(tab: tab, model: model))
            host.sizingOptions = .preferredContentSize
            host.title = tab.title
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let tabViewItem { onSelect?(tabView.indexOfTabViewItem(tabViewItem)) }
    }

    /// A window for these tabs, with the standard settings window chrome.
    public func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: self)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        return window
    }
}
