import Foundation
import MonitorCore

/// State behind the popover. Created when the popover opens and released when it closes.
@MainActor
public final class PopoverModel: ObservableObject {
    @Published public var snapshot: Snapshot
    @Published public var range: HistoryRange = .seconds30 {
        didSet { onRangeChange?(range) }
    }
    @Published public var launchAtLogin: Bool
    /// Local and public IP addresses; `nil` hides them.
    @Published public var addresses: NetworkAddresses?

    public var onRangeChange: ((HistoryRange) -> Void)?
    /// Applies the launch-at-login setting and returns the resulting state.
    public var setLaunchAtLogin: ((Bool) -> Bool)?
    public var quit: (() -> Void)?
    /// Set only when in-app updates are available.
    public var checkForUpdates: (() -> Void)?
    /// App icons for the process list, kept only as long as the popover is open.
    let icons = IconCache()

    public init(snapshot: Snapshot, launchAtLogin: Bool = false) {
        self.snapshot = snapshot
        self.launchAtLogin = launchAtLogin
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = setLaunchAtLogin?(enabled) ?? enabled
    }
}
