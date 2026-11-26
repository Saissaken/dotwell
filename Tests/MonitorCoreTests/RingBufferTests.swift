import XCTest
@testable import MonitorCore

final class RingBufferTests: XCTestCase {
    func testEmpty() {
        let buf = RingBuffer(capacity: 3)
        XCTAssertNil(buf.last)
        XCTAssertEqual(buf.values, [])
    }

    func testAppendBelowCapacity() {
        var buf = RingBuffer(capacity: 3)
        buf.append(1); buf.append(2)
        XCTAssertEqual(buf.values, [1, 2])
        XCTAssertEqual(buf.last, 2)
    }

    func testOverwritesOldest() {
        var buf = RingBuffer(capacity: 3)
        for v in 1...5 { buf.append(Float(v)) }
        XCTAssertEqual(buf.values, [3, 4, 5])
        XCTAssertEqual(buf.count, 3)
        XCTAssertEqual(buf.last, 5)
    }

    func testHealthOrdering() {
        XCTAssertEqual([HealthLevel.ok, .critical, .warning].max(), .critical)
    }
}
