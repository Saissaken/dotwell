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

    public var onRangeChange: ((HistoryRange) -> Void)?
    /// Applies the launch-at-login setting and returns the resulting state.
    public var setLaunchAtLogin: ((Bool) -> Bool)?
    public var quit: (() -> Void)?

    public init(snapshot: Snapshot, launchAtLogin: Bool = false) {
        self.snapshot = snapshot
        self.launchAtLogin = launchAtLogin
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = setLaunchAtLogin?(enabled) ?? enabled
    }
}
