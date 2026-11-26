import AppKit
import Combine
import SwiftUI

/// The Settings window, laid out like System Settings: a sidebar with a search field and colored icons,
/// grouped pages on the right, and Back and Forward buttons next to the page title.
public final class SettingsSplitViewController: NSSplitViewController, NSToolbarDelegate {
    public let navigation: SettingsNavigation
    private let model: SettingsModel
    private var observers: Set<AnyCancellable> = []
    private let backForward = NSSegmentedControl()

    public static let size = NSSize(width: 715, height: 620)
    private static let backForwardItem = NSToolbarItem.Identifier("backForward")

    public init(model: SettingsModel, page: SettingsPage = .general) {
        self.model = model
        navigation = SettingsNavigation(page: page)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        splitView.dividerStyle = .thin

        let sidebar = NSHostingController(rootView: SettingsSidebar(navigation: navigation, settings: model.settings))
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 215
        sidebarItem.maximumThickness = 215
        addSplitViewItem(sidebarItem)

        let detail = NSHostingController(rootView: SettingsDetail(navigation: navigation, model: model))
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 500
        addSplitViewItem(detailItem)

        backForward.segmentCount = 2
        backForward.trackingMode = .momentary
        backForward.segmentStyle = .separated
        backForward.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back"), forSegment: 0)
        backForward.setImage(
            NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward"), forSegment: 1)
        backForward.setToolTip("Back", forSegment: 0)
        backForward.setToolTip("Forward", forSegment: 1)
        backForward.target = self
        backForward.action = #selector(backOrForward(_:))

        navigation.$page
            .combineLatest(navigation.$canGoBack, navigation.$canGoForward)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] page, canGoBack, canGoForward in
                self?.view.window?.title = page.title
                self?.backForward.setEnabled(canGoBack, forSegment: 0)
                self?.backForward.setEnabled(canGoForward, forSegment: 1)
            }
            .store(in: &observers)
    }

    @objc private func backOrForward(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 { navigation.goBack() } else { navigation.goForward() }
    }

    /// A window for this controller, with System Settings' chrome: full-height sidebar, unified toolbar.
    public func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: self)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = navigation.page.title
        window.titlebarSeparatorStyle = .automatic
        let toolbar = NSToolbar(identifier: "Settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.setContentSize(Self.size)
        // Fixed width like System Settings; the height follows the person.
        window.contentMinSize = NSSize(width: Self.size.width, height: 420)
        window.contentMaxSize = NSSize(width: Self.size.width, height: 2000)
        return window
    }

    // MARK: - NSToolbarDelegate

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator, Self.backForwardItem]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    public func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard identifier == Self.backForwardItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = backForward
        item.label = "Back/Forward"
        item.isNavigational = true
        return item
    }
}
