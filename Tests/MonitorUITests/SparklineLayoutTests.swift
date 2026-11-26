import XCTest

@testable import MonitorUI

final class SparklineLayoutTests: XCTestCase {
    /// While the 30 s window fills, points must keep their spacing and only move left as new ones arrive:
    /// stretching the few points over the whole width made the line jump sideways with every reading.
    func testAFillingChartKeepsItsSpacingAndEndsAtTheRightEdge() {
        let full = SparklineLayout(count: 60, capacity: 60, slide: nil, width: 236)
        for count in 2...60 {
            let filling = SparklineLayout(count: count, capacity: 60, slide: nil, width: 236)
            XCTAssertEqual(filling.step, full.step, accuracy: 1e-9, "\(count) points")
            XCTAssertEqual(filling.x(count - 1), 236, accuracy: 1e-9, "the newest point is at the right edge")
            XCTAssertEqual(filling.x(0), CGFloat(60 - count) * full.step, accuracy: 1e-9)
        }
    }

    func testEachPointMovesExactlyOneStepLeftWhenTheNextArrives() {
        for count in 2..<60 {
            let before = SparklineLayout(count: count, capacity: 60, slide: nil, width: 300)
            let after = SparklineLayout(count: count + 1, capacity: 60, slide: nil, width: 300)
            for i in 0..<count {
                // Point i before the new reading is point i in `after` too (values are oldest → newest).
                XCTAssertEqual(before.x(i) - after.x(i), before.step, accuracy: 1e-9)
            }
        }
    }

    func testSlidingKeepsTheSameSpacingWhileFilling() {
        let full = SparklineLayout(count: 60, capacity: 60, slide: 0.5, width: 236)
        let filling = SparklineLayout(count: 10, capacity: 60, slide: 0.5, width: 236)
        XCTAssertEqual(filling.step, full.step, accuracy: 1e-9)
        XCTAssertEqual(filling.x(9), full.x(59), accuracy: 1e-9, "newest points line up")
        XCTAssertEqual(full.x(59), 236 + 0.5 * full.step, accuracy: 1e-9, "half a step past the right edge")
        XCTAssertLessThan(full.x(0), 0, "the lead-in sits past the left edge")
        XCTAssertEqual(SparklineLayout(count: 60, capacity: 60, slide: 0, width: 236).x(59), 236, accuracy: 1e-9)
    }

    func testWithoutACapacityTheValuesFillTheWidth() {
        let layout = SparklineLayout(count: 5, capacity: nil, slide: nil, width: 100)
        XCTAssertEqual(layout.x(0), 0)
        XCTAssertEqual(layout.x(4), 100)
    }

    func testMoreValuesThanTheCapacityStillFit() {
        let layout = SparklineLayout(count: 80, capacity: 60, slide: nil, width: 100)
        XCTAssertEqual(layout.x(0), 0)
        XCTAssertEqual(layout.x(79), 100, accuracy: 1e-9)
    }
}
