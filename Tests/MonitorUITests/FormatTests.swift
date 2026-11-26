import XCTest

@testable import MonitorUI

final class FormatTests: XCTestCase {
    func testStorageUsesDecimalUnitsWithOneDecimal() {
        // System Settings reported "248.62 GB" available on a 994.66 GB volume.
        XCTAssertEqual(Format.storage(248_620_000_000), Reading(value: "248.6", unit: "GB"))
        XCTAssertEqual(Format.storage(9_960_000_000), Reading(value: "10.0", unit: "GB"))
        XCTAssertEqual(Format.storage(512_000_000), Reading(value: "0.5", unit: "GB"))
    }

    func testStorageSwitchesToTerabytes() {
        XCTAssertEqual(Format.storage(1_234_000_000_000), Reading(value: "1.23", unit: "TB"))
    }

    func testMemoryStaysInBinaryUnits() {
        XCTAssertEqual(Format.gigabytes(17_179_869_184), Reading(value: "16.0", unit: "GB"))
    }
}
