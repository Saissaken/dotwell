import Foundation
import MonitorCore

/// State behind the popover. Created when the popover opens and released when it closes.
@MainActor
public final class PopoverModel: ObservableObject {
    @Published public var snapshot: Snapshot
    @Published public var range: HistoryRange = .seconds30 {
        didSet { onRangeChange?(range) }
    }

    public var onRangeChange: ((HistoryRange) -> Void)?
    public var openSettings: (() -> Void)?
    public var quit: (() -> Void)?
    /// Set only when in-app updates are available.
    public var checkForUpdates: (() -> Void)?
    /// Icons of the top apps, kept only as long as the popover is open.
    let icons = IconCache()

    public init(snapshot: Snapshot) {
        self.snapshot = snapshot
    }
}
