/// Time ranges offered in the popover.
public enum HistoryRange: Int, CaseIterable, Sendable {
    case seconds30, minutes5, hour1

    public var label: String {
        switch self {
        case .seconds30: return "30 s"
        case .minutes5: return "5 min"
        case .hour1: return "1 h"
        }
    }
}

/// One metric's history at three resolutions, fed one sample per tick.
/// Memory is fixed at allocation: 60 + 60 + 120 floats.
/// Negative samples mean "missing" (e.g. lost ping) and are excluded from averages;
/// a bucket with no valid sample is stored as missing.
public struct TieredSeries: Sendable {
    private var raw = RingBuffer(capacity: 60)       // 1 per sample
    private var mid = RingBuffer(capacity: 60)       // avg of 5 samples
    private var long = RingBuffer(capacity: 120)     // avg of 30 samples
    private var midAcc = Accumulator(size: 5)
    private var longAcc = Accumulator(size: 30)

    public init() {}

    public mutating func append(_ value: Float) {
        raw.append(value)
        if let v = midAcc.add(value) { mid.append(v) }
        if let v = longAcc.add(value) { long.append(v) }
    }

    public var last: Float? { raw.last }

    /// Samples for a range, oldest → newest. 30 s returns the last 30 raw samples.
    public func values(for range: HistoryRange) -> [Float] {
        switch range {
        case .seconds30: return Array(raw.values.suffix(30))
        case .minutes5: return mid.values
        case .hour1: return long.values
        }
    }

    /// Last `n` raw samples.
    public func recent(_ n: Int) -> [Float] { Array(raw.values.suffix(n)) }

    public mutating func removeAll() {
        self = TieredSeries()
    }

    private struct Accumulator: Sendable {
        let size: Int
        var sum: Float = 0
        var valid = 0
        var seen = 0

        init(size: Int) { self.size = size }

        mutating func add(_ v: Float) -> Float? {
            if v >= 0 { sum += v; valid += 1 }
            seen += 1
            guard seen == size else { return nil }
            defer { sum = 0; valid = 0; seen = 0 }
            return valid > 0 ? sum / Float(valid) : -1
        }
    }
}
