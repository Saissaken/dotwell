/// The latest readings of one ping row, each with the history slot it arrived in (see `TieredSeries`), so "the
/// last minute" counts every reply once whatever the reading interval was. The history itself repeats a
/// reading over the slots it stands for, which is right for averages over time but would hide jitter.
/// Memory is fixed at allocation.
public struct PingReadingLog: Sendable {
    /// A minute of readings every 0.5 s, the fastest interval, plus a few.
    public static let capacity = 128

    private var values = [Float](repeating: 0, count: capacity)
    private var arrivals = [UInt64](repeating: 0, count: capacity)
    private var head = 0
    public private(set) var count = 0

    public init() {}

    /// Records a reading (`PingStats.lost` when lost) that arrived in `slot`.
    public mutating func append(_ value: Float, slot: UInt64) {
        values[head] = value
        arrivals[head] = slot
        head = (head + 1) % Self.capacity
        count = min(count + 1, Self.capacity)
    }

    /// The readings that arrived after `slot`, oldest first, and the slot of the oldest one.
    public func readings(after slot: UInt64) -> (values: [Float], firstSlot: UInt64?) {
        var out: [Float] = []
        var first: UInt64?
        for i in 0..<count {
            let index = (head - count + i + Self.capacity) % Self.capacity
            guard arrivals[index] > slot else { continue }
            if first == nil { first = arrivals[index] }
            out.append(values[index])
        }
        return (out, first)
    }
}
