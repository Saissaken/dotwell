/// How often the sampler takes a reading, in milliseconds. The popover has its own, faster choices: while it
/// is closed the readings only keep the menu bar light current, and they run all day.
public enum SamplingInterval: Int, CaseIterable, Codable, Comparable, Sendable {
    case halfSecond = 500
    case oneSecond = 1000
    case twoSeconds = 2000
    case fiveSeconds = 5000
    case tenSeconds = 10000
    case thirtySeconds = 30000

    /// Choices while the popover is open: it is only on screen for a moment, so faster is fine.
    public static let whileOpen: [SamplingInterval] = [.halfSecond, .oneSecond, .twoSeconds]
    /// Choices while the popover is closed.
    public static let whileClosed: [SamplingInterval] = [
        .oneSecond, .twoSeconds, .fiveSeconds, .tenSeconds, .thirtySeconds,
    ]

    public var milliseconds: Int { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Half-second history slots one reading covers (see `TieredSeries`).
    public var slots: Int { rawValue / TieredSeries.slotMilliseconds }

    public var label: String {
        switch self {
        case .halfSecond: return "Every 0.5 seconds"
        case .oneSecond: return "Every second"
        default: return "Every \(rawValue / 1000) seconds"
        }
    }

    /// The closest choice to a saved number of seconds, for settings saved before the open and closed split.
    public init(legacySeconds seconds: Int) {
        let ms = seconds * 1000
        self = Self.allCases.min { abs($0.rawValue - ms) < abs($1.rawValue - ms) } ?? .oneSecond
    }
}

/// Everything about sampling that can change while the app runs. The sampler applies a new
/// configuration on the next tick, without restarting or losing history.
public struct SamplerConfiguration: Sendable, Equatable {
    /// Reading interval while the popover is open.
    public var openInterval: SamplingInterval
    /// Reading interval while the popover is closed. Keeps the menu bar light current all day.
    public var closedInterval: SamplingInterval
    public var targets: [PingTarget]
    /// Index into `targets` of the host that drives the ping alert.
    public var primaryIndex: Int
    public var thresholds: Thresholds
    /// Metrics allowed to raise a warning. The others always read as healthy.
    public var alerts: Set<MetricKind>
    /// False stops all ping traffic (the ping card is hidden and its alert is off).
    public var pingEnabled: Bool
    /// False skips per-app sampling even while the popover is open.
    public var sampleTopApps: Bool
    /// False leaves the GPU alone even while the popover is open (its card is hidden).
    public var sampleGPU: Bool

    public init(
        openInterval: SamplingInterval = .oneSecond,
        closedInterval: SamplingInterval = .fiveSeconds,
        targets: [PingTarget] = PingTarget.defaults,
        primaryIndex: Int = PingTarget.defaultPrimaryIndex,
        thresholds: Thresholds = Thresholds(),
        alerts: Set<MetricKind> = MetricKind.alertable,
        pingEnabled: Bool = true,
        sampleTopApps: Bool = true,
        sampleGPU: Bool = true
    ) {
        self.openInterval = openInterval
        self.closedInterval = closedInterval
        self.targets = targets
        self.primaryIndex = primaryIndex
        self.thresholds = thresholds
        self.alerts = alerts
        self.pingEnabled = pingEnabled
        self.sampleTopApps = sampleTopApps
        self.sampleGPU = sampleGPU
    }

    /// The targets actually probed.
    var activeTargets: [PingTarget] { pingEnabled ? targets : [] }

    /// `primaryIndex` clamped to the active targets.
    var activePrimaryIndex: Int { min(max(0, primaryIndex), max(0, activeTargets.count - 1)) }
}
