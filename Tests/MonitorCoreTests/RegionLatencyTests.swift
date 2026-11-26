import XCTest

@testable import MonitorCore

final class RegionLatencyTests: XCTestCase {
    /// The chooser measures a region the same way as its row in the popover, so both agree.
    func testLiveReadingMatchesThePopoverRow() throws {
        let region = try XCTUnwrap(CloudRegion.find(.aws, "us-east-1"))
        let latency = RegionLatency(regions: [region, CloudRegion.defaultFirst], rounds: 3)
        var final: [String: RegionLatency.Reading] = [:]
        let done = expectation(description: "rounds")
        done.assertForOverFulfill = false
        latency.onUpdate = { readings in
            final = readings
            if !readings.values.contains(.measuring) { done.fulfill() }
        }
        latency.start()
        wait(for: [done], timeout: 15)
        latency.stop()
        guard case .milliseconds(let chooser) = final[region.id] else {
            throw XCTSkip("No answer from \(region.host) here")
        }
        let row = try XCTUnwrap(rowMinimum(region.target), "the row got no answer while the chooser did")
        print("region chooser \(chooser) row \(row)")
        XCTAssertGreaterThan(chooser, 0)
        XCTAssertLessThan(abs(chooser - row), max(10, row * 0.25))
    }

    /// Two rounds publish three times (after each round, and the final result), then the probing stops.
    func testStopsAfterItsRounds() {
        let latency = RegionLatency(regions: [CloudRegion.defaultFirst], rounds: 2)
        var updates = 0
        latency.onUpdate = { _ in updates += 1 }
        latency.start()
        let later = expectation(description: "rounds and then some")
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { later.fulfill() }
        wait(for: [later], timeout: 10)
        XCTAssertEqual(updates, 3)
    }

    /// Lowest round trip of a few probes, like the popover row.
    private func rowMinimum(_ target: PingTarget) -> Float? {
        let queue = DispatchQueue(label: "region-latency.row")
        let engine = PingEngine(targets: [target], queue: queue)
        engine.timeoutNanos = 1_500_000_000
        var results: [Float] = []
        engine.onResult = { _, ms in if let ms { results.append(ms) } }
        for _ in 0..<4 {
            queue.sync {
                engine.collect()
                engine.probe([0])
            }
            Thread.sleep(forTimeInterval: 1.5)
        }
        return queue.sync {
            engine.collect()
            return results.min()
        }
    }
}
