import Foundation
import XCTest

@testable import MonitorCore

final class DiskProbeTests: XCTestCase {
    func testSpaceMatchesAFreshVolumeQuery() throws {
        let probe = DiskProbe()
        _ = probe.space()  // Prime any resource value cache.

        let space = try XCTUnwrap(probe.space())
        let fresh = try URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ])
        let available = try XCTUnwrap(fresh.volumeAvailableCapacityForImportantUsage)
        let total = try XCTUnwrap(fresh.volumeTotalCapacity)

        XCTAssertEqual(space.totalBytes, UInt64(total))
        XCTAssertGreaterThan(space.availableBytes, 0)
        XCTAssertLessThanOrEqual(space.availableBytes, space.totalBytes)
        // Free space moves while tests run; allow 1 GB of drift between the two reads.
        XCTAssertLessThan(abs(Double(space.availableBytes) - Double(available)), 1e9)
    }
}
