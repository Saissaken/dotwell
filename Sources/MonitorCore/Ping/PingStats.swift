/// Summary of a window of ping samples. Samples are RTTs in milliseconds; a negative value means lost.
public struct PingStats: Equatable, Sendable {
    public static let lost: Float = -1

    public var latestMs: Float?
    public var averageMs: Float?
    public var minMs: Float?
    public var maxMs: Float?
    /// 0...1
    public var lossFraction: Float
    /// Mean absolute difference between consecutive successful replies (RFC 3550-style, unsmoothed).
    public var jitterMs: Float?
    /// True when the most recent sample was lost.
    public var lastLost: Bool

    public static func compute(_ samples: [Float]) -> PingStats {
        guard !samples.isEmpty else {
            return PingStats(
                latestMs: nil, averageMs: nil, minMs: nil, maxMs: nil, lossFraction: 0, jitterMs: nil, lastLost: false)
        }
        var sum: Float = 0
        var ok = 0
        var minValue: Float?
        var maxValue: Float?
        var jitterSum: Float = 0
        var jitterCount = 0
        var previous: Float?
        var latest: Float?
        for s in samples {
            guard s >= 0 else { continue }
            sum += s
            ok += 1
            minValue = min(minValue ?? s, s)
            maxValue = max(maxValue ?? s, s)
            if let p = previous { jitterSum += abs(s - p); jitterCount += 1 }
            previous = s
            latest = s
        }
        let last = samples[samples.count - 1]
        return PingStats(
            latestMs: last >= 0 ? last : latest,
            averageMs: ok > 0 ? sum / Float(ok) : nil,
            minMs: minValue,
            maxMs: maxValue,
            lossFraction: Float(samples.count - ok) / Float(samples.count),
            jitterMs: jitterCount > 0 ? jitterSum / Float(jitterCount) : nil,
            lastLost: last < 0
        )
    }
}
