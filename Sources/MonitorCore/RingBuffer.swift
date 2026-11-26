/// Fixed-capacity circular buffer of Float32 samples. Allocates once, never grows.
public struct RingBuffer: Sendable {
    private var storage: [Float]
    private var head = 0          // index of the next write
    public private(set) var count = 0

    public var capacity: Int { storage.count }

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        storage = [Float](repeating: 0, count: capacity)
    }

    public mutating func append(_ value: Float) {
        storage[head] = value
        head = (head + 1) % storage.count
        if count < storage.count { count += 1 }
    }

    /// Most recent sample, if any.
    public var last: Float? {
        guard count > 0 else { return nil }
        return storage[(head - 1 + storage.count) % storage.count]
    }

    /// Samples ordered oldest → newest.
    public var values: [Float] {
        guard count > 0 else { return [] }
        let start = (head - count + storage.count) % storage.count
        var out = [Float]()
        out.reserveCapacity(count)
        for i in 0..<count { out.append(storage[(start + i) % storage.count]) }
        return out
    }

    public mutating func removeAll() {
        head = 0
        count = 0
    }
}
