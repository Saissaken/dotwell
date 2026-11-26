import XCTest

@testable import MonitorCore

final class HealthTests: XCTestCase {
    func testDebouncerRaisesAfterStreak() {
        var d = LevelDebouncer(raiseWarning: 3, raiseCritical: 5, lowerAfter: 2)
        XCTAssertEqual(d.feed(.warning), .ok)
        XCTAssertEqual(d.feed(.warning), .ok)
        XCTAssertEqual(d.feed(.warning), .warning)
    }

    func testDebouncerResetsOnInterruption() {
        var d = LevelDebouncer(raiseWarning: 3, raiseCritical: 3, lowerAfter: 2)
        d.feed(.warning); d.feed(.warning); d.feed(.ok)
        XCTAssertEqual(d.feed(.warning), .ok)
    }

    func testDebouncerLowers() {
        var d = LevelDebouncer(raiseWarning: 1, raiseCritical: 1, lowerAfter: 2)
        d.feed(.critical)
        XCTAssertEqual(d.feed(.ok), .critical)
        XCTAssertEqual(d.feed(.ok), .ok)
    }

    func testPingThresholds() {
        let t = Thresholds()
        XCTAssertEqual(t.ping(PingStats.compute([20, 22, 21])), .ok)
        XCTAssertEqual(t.ping(PingStats.compute([100, 110, 90])), .warning)
        XCTAssertEqual(t.ping(PingStats.compute([250, 260])), .critical)
        XCTAssertEqual(t.ping(PingStats.compute([20, PingStats.lost, PingStats.lost])), .critical)
        XCTAssertEqual(t.ping(PingStats.compute([PingStats.lost])), .critical)
    }

    func testCPUAndDisk() {
        let t = Thresholds()
        XCTAssertEqual(t.cpu(0.5), .ok)
        XCTAssertEqual(t.cpu(0.85), .warning)
        XCTAssertEqual(t.cpu(0.99), .critical)
        XCTAssertEqual(t.disk(DiskSpace(availableBytes: 10, totalBytes: 100)), .warning)
        XCTAssertEqual(t.disk(DiskSpace(availableBytes: 1, totalBytes: 100)), .critical)
    }

    func testThermalStateMapsToLevels() {
        let t = Thresholds()
        XCTAssertEqual(t.thermal(.nominal), .ok)
        XCTAssertEqual(t.thermal(.fair), .ok)
        XCTAssertEqual(t.thermal(.serious), .warning)
        XCTAssertEqual(t.thermal(.critical), .critical)
    }

    func testTieredSeriesDownsamples() {
        var s = TieredSeries()
        for i in 0..<20 { s.append(Float(i)) }
        XCTAssertEqual(s.values(for: .minutes5), [4.5, 14.5])  // avg(0..9), avg(10..19): 5 s each
        XCTAssertEqual(s.values(for: .seconds30).count, 20)
    }

    func testTieredSeriesSkipsMissing() {
        var s = TieredSeries()
        for v: Float in [10, -1, 20, -1, -1, -1, -1, -1, -1, -1] { s.append(v) }
        XCTAssertEqual(s.values(for: .minutes5), [15])
        var lost = TieredSeries()
        lost.append(-1, slots: 10)
        XCTAssertEqual(lost.values(for: .minutes5), [-1])
    }

    /// A reading fills the slots it stands for, so the time scale holds when the interval changes.
    func testTieredSeriesHoldsSlowReadings() {
        var s = TieredSeries()
        s.append(10, slots: 10)  // one reading 5 s after the last: the popover was closed
        for _ in 0..<10 { s.append(20) }  // then ten every 0.5 s
        XCTAssertEqual(s.values(for: .minutes5), [10, 20])
        XCTAssertEqual(s.recent(12), [10, 10] + Array(repeating: 20, count: 10))
        // Lost replies keep their share of the time: one of two 5 s readings lost is half the window.
        var ping = TieredSeries()
        ping.append(30, slots: 10)
        ping.append(-1, slots: 10)
        XCTAssertEqual(PingStats.compute(ping.recent(20)).lossFraction, 0.5, accuracy: 1e-6)
    }

    func testDebouncerCountsTime() {
        var d = LevelDebouncer(raiseWarning: 6, raiseCritical: 6, lowerAfter: 10)  // 3 s and 5 s in slots
        XCTAssertEqual(d.feed(.warning, weight: 2), .ok)  // 1 s
        XCTAssertEqual(d.feed(.warning, weight: 10), .warning, "one 5 s reading covers the 3 s hold")
        XCTAssertEqual(d.feed(.ok, weight: 10), .ok)
    }

    func testSamplerProducesSnapshots() {
        let sampler = Sampler(targets: [PingTarget(name: "lo", host: "127.0.0.1", method: .icmp)], primaryIndex: 0)
        let got = expectation(description: "snapshot")
        got.assertForOverFulfill = false
        var last: Snapshot?
        sampler.onSnapshot = { snap in
            last = snap
            if snap.cpu != nil, !(snap.primaryPing?.stats.averageMs == nil) { got.fulfill() }
        }
        sampler.setDetailed(true, range: .seconds30)
        sampler.start()
        wait(for: [got], timeout: 6)
        sampler.stop()
        XCTAssertNotNil(last?.memory)
        XCTAssertNotNil(last?.history[SeriesKey.cpu])
    }

    /// With the popover closed, the main queue only hears about level changes: the menu bar dot is all that
    /// shows them, and each delivery would wake the main thread once a second.
    func testClosedSamplerOnlyPublishesLevelChanges() {
        let sampler = Sampler(configuration: SamplerConfiguration(closedInterval: .oneSecond, targets: []))
        var count = 0
        let counted = expectation(description: "ticks")
        sampler.onSnapshot = { _ in count += 1 }
        sampler.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { counted.fulfill() }
        wait(for: [counted], timeout: 6)
        sampler.stop()
        XCTAssertLessThan(count, 3, "the first level and at most one change, not one per tick")
        XCTAssertNotNil(sampler.latest().cpu, "fresh values are still there for when the popover opens")
    }
}

extension HealthTests {
    /// Opening the popover switches to its own, faster interval right away.
    func testOpenPopoverUsesItsOwnInterval() {
        let sampler = Sampler(
            configuration: SamplerConfiguration(openInterval: .halfSecond, closedInterval: .thirtySeconds, targets: []))
        var count = 0
        sampler.onSnapshot = { _ in count += 1 }
        sampler.start()
        sampler.setDetailed(true, range: .seconds30)
        let counted = expectation(description: "ticks")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { counted.fulfill() }
        wait(for: [counted], timeout: 5)
        sampler.stop()
        // One snapshot on opening, then one every 0.5 s: about 5, never the 0 or 1 a 30 s interval gives.
        XCTAssertGreaterThanOrEqual(count, 4)
    }
}

final class ChartMotionTests: XCTestCase {
    func testProgressSlidesOverOnePeriod() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let raw = ChartMotion(takenAt: start, phase: 0, period: 1)
        XCTAssertEqual(raw.progress(at: start), 0)
        XCTAssertEqual(raw.progress(at: start.addingTimeInterval(0.25)), 0.25, accuracy: 1e-9)
        XCTAssertEqual(raw.progress(at: start.addingTimeInterval(3)), 1, "rests when the next tick is late")
        // 5 min range: 3 of the 5 samples of the next point are already in.
        let averaged = ChartMotion(takenAt: start, phase: 0.6, period: 5)
        XCTAssertEqual(averaged.progress(at: start.addingTimeInterval(1)), 0.8, accuracy: 1e-9)
    }
}
