import Foundation
import MonitorCore

/// Exists only while the popover is open.
@MainActor
final class PopoverModel: ObservableObject {
    @Published var snapshot: Snapshot
    @Published var range: HistoryRange = .seconds30 {
        didSet { onRangeChange?(range) }
    }
    var onRangeChange: ((HistoryRange) -> Void)?

    init(snapshot: Snapshot) {
        self.snapshot = snapshot
    }
}
