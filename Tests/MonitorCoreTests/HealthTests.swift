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

    func testTieredSeriesDownsamples() {
        var s = TieredSeries()
        for i in 0..<10 { s.append(Float(i)) }
        XCTAssertEqual(s.values(for: .minutes5), [2, 7])  // avg(0..4), avg(5..9)
        XCTAssertEqual(s.values(for: .seconds30).count, 10)
    }

    func testTieredSeriesSkipsMissing() {
        var s = TieredSeries()
        for v: Float in [10, -1, 20, -1, -1] { s.append(v) }
        XCTAssertEqual(s.values(for: .minutes5), [15])
        var lost = TieredSeries()
        for _ in 0..<5 { lost.append(-1) }
        XCTAssertEqual(lost.values(for: .minutes5), [-1])
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
}
