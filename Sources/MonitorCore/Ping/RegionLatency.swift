import Foundation

/// Measures every region of a provider a few times, for the region chooser in Settings. It only runs while
/// the chooser is open, with its own `PingEngine`, so the popover's history and rows are never touched.
///
/// Each region is measured the same way as its row in the popover (a TCP handshake, or a small HTTPS
/// request for Google Cloud), and the best of the rounds is reported: the lowest round trip is the
/// path's real latency, the others only add queueing on the way.
public final class RegionLatency: @unchecked Sendable {
    /// A region's best round trip so far.
    public enum Reading: Equatable, Sendable {
        case measuring
        case milliseconds(Float)
        /// No answer in any round.
        case noAnswer
    }

    public let regions: [CloudRegion]
    /// Called on the main queue after each round, keyed by `CloudRegion.id`.
    public var onUpdate: (([String: Reading]) -> Void)?

    private let queue = DispatchQueue(label: "monitor.region-latency", qos: .utility)
    private let engine: PingEngine
    private var timer: DispatchSourceTimer?
    private var best: [Int: Float] = [:]
    private var answered = Set<Int>()
    private var round = 0
    private let rounds: Int

    /// - Parameter rounds: how many times each region is measured. The first round mostly resolves
    ///   addresses, so at least two are needed.
    public init(regions: [CloudRegion], rounds: Int = 4) {
        self.regions = regions
        self.rounds = max(2, rounds)
        engine = PingEngine(targets: regions.map(\.target), queue: queue)
        engine.timeoutNanos = 1_500_000_000
        engine.onResult = { [weak self] index, ms in
            guard let self, let ms else { return }
            answered.insert(index)
            best[index] = min(best[index] ?? .infinity, ms)
        }
    }

    deinit {
        timer?.cancel()
    }

    public func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.setEventHandler { [weak self] in self?.nextRound() }
            t.schedule(deadline: .now(), repeating: .milliseconds(1500), leeway: .milliseconds(100))
            timer = t
            t.resume()
        }
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            engine.reset()
        }
    }

    private func nextRound() {
        engine.collect()
        publish(final: round >= rounds)
        guard round < rounds else {
            timer?.cancel()
            timer = nil
            engine.reset()
            return
        }
        round += 1
        engine.probe(Array(regions.indices))
    }

    private func publish(final: Bool) {
        var readings: [String: Reading] = [:]
        for (i, region) in regions.enumerated() {
            if let ms = best[i] {
                readings[region.id] = .milliseconds(ms)
            } else {
                // Before the last round, a region that hasn't answered may just be resolving its address.
                readings[region.id] = final && !answered.contains(i) ? .noAnswer : .measuring
            }
        }
        guard let onUpdate else { return }
        DispatchQueue.main.async { onUpdate(readings) }
    }
}
