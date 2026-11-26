import AppKit
import XCTest

@testable import MonitorUI

final class FormatTests: XCTestCase {
    // MARK: - Three significant digits

    func testSignificantKeepsAtMostThreeDigits() {
        XCTAssertEqual(Format.significant(0), "0")
        XCTAssertEqual(Format.significant(0.04), "0")
        XCTAssertEqual(Format.significant(0.05), "0.1")
        XCTAssertEqual(Format.significant(9.94), "9.9")
        XCTAssertEqual(Format.significant(12.34), "12.3")
        XCTAssertEqual(Format.significant(99.94), "99.9")
        XCTAssertEqual(Format.significant(99.96), "100")
        XCTAssertEqual(Format.significant(773.4), "773")
        XCTAssertEqual(Format.significant(-3), "0")
    }

    func testScaledSwitchesUnitInsteadOfGrowing() {
        let units = ["KB/s", "MB/s", "GB/s"]
        XCTAssertEqual(Format.scaled(999.4, units: units), Reading(value: "999", unit: "KB/s"))
        XCTAssertEqual(Format.scaled(999.6, units: units), Reading(value: "1.0", unit: "MB/s"))
        XCTAssertEqual(Format.scaled(123_400, units: units), Reading(value: "123", unit: "MB/s"))
        XCTAssertEqual(Format.scaled(.infinity, units: units), Reading(value: "0", unit: "KB/s"))
        // The last unit grows rather than lying about the value.
        XCTAssertEqual(Format.scaled(4_200_000_000, units: units), Reading(value: "4200", unit: "GB/s"))
    }

    func testEveryValueFitsInFourCharacters() {
        var samples: [Double] = [0, 0.5, 1]
        var value = 1.0
        while value < 1e13 {
            value *= 1.37
            samples.append(value)
        }
        for sample in samples {
            for reading in [
                Format.bytes(sample), Format.bits(sample), Format.storage(UInt64(sample)),
                Format.gigabytes(UInt64(sample)), Format.watts(min(sample / 1e9, 999)),
                Format.ms(Float(sample / 1e7)),
            ] {
                XCTAssertLessThanOrEqual(reading.value.count, 4, "\(sample) → \(reading.text)")
            }
            XCTAssertLessThanOrEqual(Format.processMemory(UInt64(sample)).count, 7)
        }
    }

    // MARK: - Units

    func testDiskCaption() {
        XCTAssertEqual(Format.diskIO(read: 123_400_000, write: 773_400), "R 123 MB/s · W 773 KB/s")
    }

    func testTransferRates() {
        XCTAssertEqual(Format.bytesPerSec(0), "0 KB/s")
        XCTAssertEqual(Format.bytesPerSec(773_400), "773 KB/s")
        XCTAssertEqual(Format.bytesPerSec(1_234_000), "1.2 MB/s")
        XCTAssertEqual(Format.bytesPerSec(123_400_000), "123 MB/s")
        XCTAssertEqual(Format.bytesPerSec(1_240_000_000), "1.2 GB/s")
    }

    func testNetworkSpeeds() {
        XCTAssertEqual(Format.bits(850_000), Reading(value: "850", unit: "kbps"))
        XCTAssertEqual(Format.bits(12_340_000), Reading(value: "12.3", unit: "Mbps"))
        XCTAssertEqual(Format.bits(312_000_000), Reading(value: "312", unit: "Mbps"))
        XCTAssertEqual(Format.bits(1_200_000_000), Reading(value: "1.2", unit: "Gbps"))
    }

    func testLatency() {
        XCTAssertEqual(Format.ms(4.24), Reading(value: "4.2", unit: "ms"))
        XCTAssertEqual(Format.ms(9.96), Reading(value: "10", unit: "ms"))
        XCTAssertEqual(Format.ms(45.4), Reading(value: "45", unit: "ms"))
        XCTAssertEqual(Format.ms(999.4), Reading(value: "999", unit: "ms"))
        XCTAssertEqual(Format.ms(1_234), Reading(value: "1.2", unit: "s"))
        XCTAssertEqual(Format.ms(nil), .none)
    }

    func testPower() {
        XCTAssertEqual(Format.watts(2.14), Reading(value: "2.1", unit: "W"))
        XCTAssertEqual(Format.watts(12.34), Reading(value: "12.3", unit: "W"))
        XCTAssertEqual(Format.watts(140.2), Reading(value: "140", unit: "W"))
        XCTAssertEqual(Format.watts(nil), .none)
    }

    func testStorageUsesDecimalUnits() {
        // System Settings reported "248.62 GB" available on a 994.66 GB volume.
        XCTAssertEqual(Format.storage(248_620_000_000), Reading(value: "249", unit: "GB"))
        XCTAssertEqual(Format.storage(9_960_000_000), Reading(value: "10.0", unit: "GB"))
        XCTAssertEqual(Format.storage(512_000_000), Reading(value: "0.5", unit: "GB"))
        XCTAssertEqual(Format.storage(1_234_000_000_000), Reading(value: "1.2", unit: "TB"))
    }

    func testMemoryStaysInBinaryUnits() {
        XCTAssertEqual(Format.gigabytes(17_179_869_184), Reading(value: "16.0", unit: "GB"))
        XCTAssertEqual(Format.gigabytes(12_240_656_793), Reading(value: "11.4", unit: "GB"))
        XCTAssertEqual(Format.gigabytes(137_438_953_472), Reading(value: "128", unit: "GB"))
    }

    func testTemperatureFollowsTheLocaleUnit() throws {
        let formatter = Format.temperatureFormatter
        let locale = formatter.locale
        defer { formatter.locale = locale }

        formatter.locale = Locale(identifier: "en_GB")
        let celsius = try XCTUnwrap(Format.temperature(52.4))
        XCTAssertTrue(celsius.contains("52") && celsius.contains("C"), celsius)

        formatter.locale = Locale(identifier: "en_US")
        let fahrenheit = try XCTUnwrap(Format.temperature(52.4))
        XCTAssertTrue(fahrenheit.contains("126") && fahrenheit.contains("F"), fahrenheit)

        XCTAssertNil(Format.temperature(nil))
    }

    func testProcessCPUUsesActivityMonitorScale() {
        XCTAssertEqual(Format.processCPU(0.042), "4.2%")
        XCTAssertEqual(Format.processCPU(0.0996), "10%")
        XCTAssertEqual(Format.processCPU(2.864), "286%")
    }

    func testProcessMemorySwitchesToGigabytes() {
        XCTAssertEqual(Format.processMemory(671_088_640), "640 MB")
        XCTAssertEqual(Format.processMemory(1_045_000_000), "997 MB")
        XCTAssertEqual(Format.processMemory(1_073_000_000), "1.0 GB")
        XCTAssertEqual(Format.processMemory(2_576_980_378), "2.4 GB")
    }

    // MARK: - Fixed-size layout

    /// Captions are drawn at one fixed size, so the widest value each one can show must fit
    /// a half-width module. If one of these fails, shorten the label rather than shrinking text.
    func testWorstCaseCaptionsFitAHalfWidthModule() {
        let size = NSFont.preferredFont(forTextStyle: .caption1).pointSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        let available = PopoverLayout.halfModuleContentWidth
        let captions = [
            Format.diskIO(read: 998_000_000, write: 998_000_000),
            Format.diskIO(read: 99_900_000, write: 99_900_000),
            "of \(Format.gigabytes(137_438_953_472).value) GB · pressure critical",
            "24 cores · 212°F",
            "Slowed down to cool · 212°F",
        ]
        for caption in captions {
            let width = (caption as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(
                width, available, "“\(caption)” is \(width) pt wide, \(available) pt available")
        }
    }
}
