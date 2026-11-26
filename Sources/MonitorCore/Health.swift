import Foundation

public enum MetricKind: String, CaseIterable, Sendable {
    case ping, cpu, memory, disk, power, network, thermal
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

    @discardableResult
    public mutating func feed(_ raw: HealthLevel) -> HealthLevel {
        if raw == level { candidate = level; streak = 0; return level }
        if raw == candidate { streak += 1 } else { candidate = raw; streak = 1 }
        let needed: Int
        if raw > level { needed = raw == .critical ? raiseCritical : raiseWarning } else { needed = lowerAfter }
        if streak >= needed { level = raw; streak = 0 }
        return level
    }
}

/// Thresholds from docs/REQUIREMENTS.md §4. All values are defaults pending confirmation.
public struct Thresholds: Sendable {
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

    public func ping(_ s: PingStats) -> HealthLevel {
        if s.averageMs == nil && s.lossFraction > 0 { return .critical } // nothing answers
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
