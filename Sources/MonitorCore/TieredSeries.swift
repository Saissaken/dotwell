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

/// One metric's history at three resolutions, on a clock of half-second slots, so the charts keep the same
/// time scale whether readings come every 0.5 s (popover open) or every 5 s (closed).
///
/// A reading fills every slot since the previous one: CPU, network and disk readings are averages over that
/// time already, and a held ping reply weighs as much as the time it stands for, so latency and loss over a
/// window stay right when the interval changes.
/// Memory is fixed at allocation: 300 + 60 + 120 floats.
/// Negative samples mean "missing" (e.g. lost ping) and are excluded from averages;
/// a bucket with no valid sample is stored as missing.
public struct TieredSeries: Sendable {
    public static let slotMilliseconds = 500
    /// Slots in one point of the 5 min and 1 h charts.
    public static let midSlots = 10  // 5 s
    public static let longSlots = 60  // 30 s

    private var raw = RingBuffer(capacity: 300)  // 1 per slot: 150 s, enough for 5 readings 30 s apart
    private var mid = RingBuffer(capacity: 60)  // avg of 10 slots
    private var long = RingBuffer(capacity: 120)  // avg of 60 slots
    private var midAcc = Accumulator(size: midSlots)
    private var longAcc = Accumulator(size: longSlots)

    public init() {}

    /// Records a reading that covers `slots` half-second slots.
    public mutating func append(_ value: Float, slots: Int = 1) {
        for _ in 0..<max(1, slots) {
            raw.append(value)
            if let v = midAcc.add(value) { mid.append(v) }
            if let v = longAcc.add(value) { long.append(v) }
        }
    }

    public var last: Float? { raw.last }

    /// Points for a chart range, oldest → newest. The 30 s chart has one point per reading, so `stepSlots` (the
    /// slots one reading covers) thins the raw slots out; the 5 min and 1 h charts have one point per 5 s and
    /// 30 s bucket.
    public func values(for range: HistoryRange, stepSlots: Int = 1) -> [Float] {
        switch range {
        case .seconds30:
            let step = max(1, stepSlots)
            let all = raw.values
            let capacity = Self.points(for: range, stepSlots: step)
            var points: [Float] = []
            var i = all.count - 1
            while i >= 0, points.count < capacity {
                points.append(all[i])
                i -= step
            }
            return points.reversed()
        case .minutes5: return mid.values
        case .hour1: return long.values
        }
    }

    /// How many points `values(for:stepSlots:)` returns once the range has filled up. Charts lay out this many
    /// slots from the start, so while history is still short the line grows in from the right at its final
    /// spacing instead of stretching across the whole width and jumping sideways with every new point.
    public static func points(for range: HistoryRange, stepSlots: Int = 1) -> Int {
        switch range {
        case .seconds30: return max(2, 60 / max(1, stepSlots))
        case .minutes5: return 60  // `mid` capacity
        case .hour1: return 120  // `long` capacity
        }
    }

    /// The last `n` slots.
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
