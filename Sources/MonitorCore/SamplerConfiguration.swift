/// How often the sampler takes a reading.
public enum SamplingInterval: Int, CaseIterable, Codable, Sendable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5
    case tenSeconds = 10

    public var seconds: Int { rawValue }

    public var label: String { rawValue == 1 ? "1 second" : "\(rawValue) seconds" }
}

/// Everything about sampling that can change while the app runs. The sampler applies a new
/// configuration on the next tick, without restarting or losing history.
public struct SamplerConfiguration: Sendable, Equatable {
    public var interval: SamplingInterval
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

    public init(
        interval: SamplingInterval = .oneSecond,
        targets: [PingTarget] = PingTarget.defaults,
        primaryIndex: Int = PingTarget.defaultPrimaryIndex,
        thresholds: Thresholds = Thresholds(),
        alerts: Set<MetricKind> = MetricKind.alertable,
        pingEnabled: Bool = true,
        sampleTopApps: Bool = true
    ) {
        self.interval = interval
        self.targets = targets
        self.primaryIndex = primaryIndex
        self.thresholds = thresholds
        self.alerts = alerts
        self.pingEnabled = pingEnabled
        self.sampleTopApps = sampleTopApps
    }

    /// The targets actually probed.
    var activeTargets: [PingTarget] { pingEnabled ? targets : [] }

    /// `primaryIndex` clamped to the active targets.
    var activePrimaryIndex: Int { min(max(0, primaryIndex), max(0, activeTargets.count - 1)) }
}
