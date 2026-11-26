import XCTest

@testable import MonitorCore

/// The numbers behind a ping row's detail: which readings make up "the last minute", and what gets traced
/// when a row asks for its route.
final class PingDetailTests: XCTestCase {
    func testProbeIntervalFollowsTheSamplingLoop() {
        // ICMP goes out every tick; TCP, HTTPS and DNS every 5 s, or every tick when ticks are further apart.
        XCTAssertEqual(Sampler.probeInterval(.icmp, interval: .halfSecond), 500)
        XCTAssertEqual(Sampler.probeInterval(.icmp, interval: .tenSeconds), 10_000)
        XCTAssertEqual(Sampler.probeInterval(.tcp(port: 443), interval: .halfSecond), 5000)
        XCTAssertEqual(Sampler.probeInterval(.https(path: "/"), interval: .twoSeconds), 5000)
        XCTAssertEqual(Sampler.probeInterval(.dns, interval: .fiveSeconds), 5000)
        XCTAssertEqual(Sampler.probeInterval(.tcp(port: 443), interval: .thirtySeconds), 30_000)
    }

    /// Each reply is counted once, whatever interval it came at, and only the last minute is kept.
    func testReadingLogKeepsTheLastMinute() {
        var log = PingReadingLog()
        // Closed popover: a reading every 5 s (10 slots) for two minutes, then open: one per slot.
        var slot: UInt64 = 0
        for i in 0..<24 {
            slot += 10
            log.append(Float(i), slot: slot)
        }
        for _ in 0..<20 {
            slot += 1
            log.append(PingStats.lost, slot: slot)
        }
        let minute = log.readings(after: slot - 120)
        // 120 slots back is 100 slots of the closed readings (10 of them) plus the 20 open ones.
        XCTAssertEqual(minute.values.count, 30)
        XCTAssertEqual(minute.values.first, 14)
        XCTAssertEqual(minute.values.filter { $0 < 0 }.count, 20)
        XCTAssertEqual(minute.firstSlot, 150)
        XCTAssertEqual(log.readings(after: slot).values, [])
    }

    /// The log holds a full minute at the fastest interval (0.5 s) and drops the oldest past that.
    func testReadingLogCapacity() {
        var log = PingReadingLog()
        for i in 1...200 { log.append(Float(i), slot: UInt64(i)) }
        XCTAssertGreaterThanOrEqual(PingReadingLog.capacity, 120)
        XCTAssertEqual(log.count, PingReadingLog.capacity)
        let all = log.readings(after: 0).values
        XCTAssertEqual(all.count, PingReadingLog.capacity)
        XCTAssertEqual(all.last, 200)
        XCTAssertEqual(all.first, Float(200 - PingReadingLog.capacity + 1))
        XCTAssertEqual(log.readings(after: 80).values.count, 120)
    }

    func testMinuteStatsAreComputedFromTheReadingsShown() {
        var state = PingTargetState(index: 0, target: .router, stats: PingStats.compute([5]), isPrimary: false)
        state.lastMinute = [4, 6, PingStats.lost, 8, 2]
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
                XCTAssertEqual(row.probeIntervalMilliseconds, 1000)  // the default open interval
                XCTAssertLessThanOrEqual(row.lastMinuteChart.count, 120)
                XCTAssertLessThanOrEqual(row.lastMinuteSeconds, 60)
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
