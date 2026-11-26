import Foundation

public enum MetricKind: String, CaseIterable, Codable, Sendable {
    case ping, cpu, memory, disk, power, network, thermal

    /// Metrics that can raise a warning. Network throughput has no healthy range.
    public static let alertable: Set<MetricKind> = [.ping, .cpu, .memory, .disk, .power, .thermal]
}

/// Debounces a raw level so the icon doesn't flicker: a higher level must hold for
/// `raiseAfter[level]` consecutive samples, a lower one for `lowerAfter`.
public struct LevelDebouncer: Sendable {
    public private(set) var level: HealthLevel = .ok
    private let raiseWarning: Int
    private let raiseCritical: Int
    private let lowerAfter: Int
    private var candidate: HealthLevel = .ok
    private var streak = 0

    public init(raiseWarning: Int, raiseCritical: Int, lowerAfter: Int) {
        self.raiseWarning = max(1, raiseWarning)
        self.raiseCritical = max(1, raiseCritical)
        self.lowerAfter = max(1, lowerAfter)
    }

    /// Back to healthy, with no pending change.
    public mutating func reset() {
        level = .ok
        candidate = .ok
        streak = 0
    }

    /// Feeds one reading that stands for `weight` units of time (the sampler uses half-second slots, so a
    /// hold means the same time whatever the reading interval).
    @discardableResult
    public mutating func feed(_ raw: HealthLevel, weight: Int = 1) -> HealthLevel {
        let weight = max(1, weight)
        if raw == level { candidate = level; streak = 0; return level }
        if raw == candidate { streak += weight } else { candidate = raw; streak = weight }
        let needed: Int
        if raw > level { needed = raw == .critical ? raiseCritical : raiseWarning } else { needed = lowerAfter }
        if streak >= needed { level = raw; streak = 0 }
        return level
    }
}

/// Alert thresholds. Defaults come from docs/REQUIREMENTS.md §4; people can change them in Settings.
public struct Thresholds: Sendable, Equatable, Codable {
    public var pingWarningMs: Float = 80
    public var pingCriticalMs: Float = 200
    public var pingLossWarning: Float = 0.02
    public var pingLossCritical: Float = 0.10
    public var cpuWarning: Float = 0.80
    public var cpuCritical: Float = 0.95
    public var diskFreeWarning: Float = 0.15
    public var diskFreeCritical: Float = 0.05
    public var batteryDrawWarningWatts: Double = 25

    public init() {}

    /// Missing keys keep their default, so settings saved by older versions still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Thresholds()
        pingWarningMs = try c.decodeIfPresent(Float.self, forKey: .pingWarningMs) ?? d.pingWarningMs
        pingCriticalMs = try c.decodeIfPresent(Float.self, forKey: .pingCriticalMs) ?? d.pingCriticalMs
        pingLossWarning = try c.decodeIfPresent(Float.self, forKey: .pingLossWarning) ?? d.pingLossWarning
        pingLossCritical = try c.decodeIfPresent(Float.self, forKey: .pingLossCritical) ?? d.pingLossCritical
        cpuWarning = try c.decodeIfPresent(Float.self, forKey: .cpuWarning) ?? d.cpuWarning
        cpuCritical = try c.decodeIfPresent(Float.self, forKey: .cpuCritical) ?? d.cpuCritical
        diskFreeWarning = try c.decodeIfPresent(Float.self, forKey: .diskFreeWarning) ?? d.diskFreeWarning
        diskFreeCritical = try c.decodeIfPresent(Float.self, forKey: .diskFreeCritical) ?? d.diskFreeCritical
        batteryDrawWarningWatts =
            try c.decodeIfPresent(Double.self, forKey: .batteryDrawWarningWatts) ?? d.batteryDrawWarningWatts
    }

    public func ping(_ s: PingStats) -> HealthLevel {
        if s.averageMs == nil && s.lossFraction > 0 { return .critical }  // nothing answers
        let avg = s.averageMs ?? 0
        if avg > pingCriticalMs || s.lossFraction > pingLossCritical { return .critical }
        if avg > pingWarningMs || s.lossFraction > pingLossWarning { return .warning }
        return .ok
    }

    public func cpu(_ usage: Float) -> HealthLevel {
        usage > cpuCritical ? .critical : usage > cpuWarning ? .warning : .ok
    }

    public func memory(_ p: MemoryPressure) -> HealthLevel {
        switch p {
        case .normal: return .ok
        case .warning: return .warning
        case .critical: return .critical
        }
    }

    public func disk(_ d: DiskSpace) -> HealthLevel {
        let f = d.freeFraction
        return f < diskFreeCritical ? .critical : f < diskFreeWarning ? .warning : .ok
    }

    public func power(_ p: PowerSample) -> HealthLevel {
        guard p.source == .battery, let w = p.watts else { return .ok }
        return w > batteryDrawWarningWatts ? .warning : .ok
    }

    public func thermal(_ t: ProcessInfo.ThermalState) -> HealthLevel {
        switch t {
        case .serious: return .warning
        case .critical: return .critical
        default: return .ok
        }
    }
}
