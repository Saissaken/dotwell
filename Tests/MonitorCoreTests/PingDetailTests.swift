import XCTest

@testable import MonitorCore

/// The numbers behind a ping row's detail: which readings make up "the last minute", and what gets traced
/// when a row asks for its route.
final class PingDetailTests: XCTestCase {
    func testProbeIntervalFollowsTheSamplingLoop() {
        // ICMP goes out every tick; TCP, HTTPS and DNS every 5 s, or every tick when ticks are 5 s or longer.
        XCTAssertEqual(Sampler.probeInterval(.icmp, step: 1), 1)
        XCTAssertEqual(Sampler.probeInterval(.icmp, step: 10), 10)
        XCTAssertEqual(Sampler.probeInterval(.tcp(port: 443), step: 1), 5)
        XCTAssertEqual(Sampler.probeInterval(.https(path: "/"), step: 2), 4)
        XCTAssertEqual(Sampler.probeInterval(.dns, step: 5), 5)
        XCTAssertEqual(Sampler.probeInterval(.tcp(port: 443), step: 10), 10)
    }

    func testLastMinuteCoversSixtySeconds() {
        XCTAssertEqual(Sampler.samplesPerMinute(.icmp, step: 1), 60)
        XCTAssertEqual(Sampler.samplesPerMinute(.icmp, step: 2), 30)
        XCTAssertEqual(Sampler.samplesPerMinute(.tcp(port: 443), step: 1), 12)
        XCTAssertEqual(Sampler.samplesPerMinute(.https(path: "/"), step: 2), 15)
        XCTAssertEqual(Sampler.samplesPerMinute(.dns, step: 10), 6)
    }

    /// The raw history holds 60 readings, so a full minute always fits.
    func testLastMinuteFitsTheHistory() {
        var series = TieredSeries()
        for i in 0..<90 { series.append(Float(i)) }
        let minute = series.recent(Sampler.samplesPerMinute(.icmp, step: 1))
        XCTAssertEqual(minute.count, 60)
        XCTAssertEqual(minute.first, 30)
        XCTAssertEqual(minute.last, 89)
    }

    func testMinuteStatsAreComputedFromTheReadingsShown() {
        let state = PingTargetState(
            index: 0, target: .router, stats: PingStats.compute([5]), isPrimary: false,
            lastMinute: [4, 6, PingStats.lost, 8, 2])
        let stats = state.minuteStats
        XCTAssertEqual(stats.averageMs, 5)
        XCTAssertEqual(stats.minMs, 2)
        XCTAssertEqual(stats.maxMs, 8)
        XCTAssertEqual(stats.lossFraction, 0.2)
        XCTAssertEqual(stats.jitterMs ?? 0, 10.0 / 3, accuracy: 0.001)  // |6-4|, |8-6|, |2-8| skip the lost one
    }

    func testTraceHost() {
        let targets: [PingTarget] = [
            .router, .isp, .dns, InternetHost.cloudflare.target, CloudRegion.defaultFirst.target,
        ]
        let found: (Int) -> String? = { ["192.168.1.1", "181.30.128.1", "192.168.1.1", nil, nil][$0] }
        func host(_ index: Int, picked: Bool) -> String? {
            Sampler.traceHost(for: index, targets: targets, picked: picked, address: found)
        }
        // The router is one hop away: nothing to trace.
        XCTAssertNil(host(0, picked: true))
        // The ISP and DNS rows are only traced when picked, to the address they are measured at.
        XCTAssertNil(host(1, picked: false))
        XCTAssertEqual(host(1, picked: true), "181.30.128.1")
        XCTAssertEqual(host(2, picked: true), "192.168.1.1")
        // Named hosts are traced by name, cloud regions included.
        XCTAssertEqual(host(3, picked: false), "1.1.1.1")
        XCTAssertEqual(host(4, picked: false), "dynamodb.sa-east-1.amazonaws.com")
        XCTAssertNil(host(9, picked: true))
    }

    /// Live: with the popover open, every row carries its readings of the last minute, and a row can take
    /// over the route trace until the popover closes.
    func testLiveLastMinuteAndTracePick() {
        let sampler = Sampler(targets: [
            PingTarget(name: "a", host: "127.0.0.1", method: .icmp),
            PingTarget(name: "b", host: "127.0.0.1", method: .icmp),
        ])
        let filled = expectation(description: "last minute filled")
        filled.assertForOverFulfill = false
        let picked = expectation(description: "route to the picked row")
        picked.assertForOverFulfill = false
        var pickRequested = false
        sampler.onSnapshot = { snap in
            guard let row = snap.ping.first else { return }
            let replies = row.lastMinute.filter { $0 >= 0 }
            if replies.count >= 3 {
                XCTAssertEqual(row.probeIntervalSeconds, 1)
                XCTAssertEqual(row.minuteStats, PingStats.compute(row.lastMinute))
                // Loopback answers in well under a millisecond or two, never in tens.
                XCTAssertLessThan(row.minuteStats.maxMs ?? .infinity, 20)
                XCTAssertGreaterThanOrEqual(row.minuteStats.minMs ?? -1, 0)
                filled.fulfill()
                if !pickRequested {
                    pickRequested = true
                    XCTAssertEqual(snap.pathIndex, 0)  // the primary row by default
                    sampler.traceRoute(to: 1)
                }
            }
            if pickRequested, snap.pathIndex == 1, snap.path != nil { picked.fulfill() }
        }
        sampler.start()
        sampler.setDetailed(true, range: .seconds30)
        wait(for: [filled, picked], timeout: 10)
        sampler.onSnapshot = nil
        sampler.stop()
    }
}
