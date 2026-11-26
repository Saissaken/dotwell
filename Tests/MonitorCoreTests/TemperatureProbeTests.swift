import XCTest

@testable import MonitorCore

final class TemperatureProbeTests: XCTestCase {
    func testFourCharacterCodes() {
        XCTAssertEqual(SMC.code("TC0P"), 0x5443_3050)
        XCTAssertEqual(SMC.code("#KEY"), 0x234B_4559)
    }

    func testDecodesAppleSiliconFloats() {
        let bytes = withUnsafeBytes(of: Float(52.5).bitPattern.littleEndian, Array.init)
        XCTAssertEqual(TemperatureProbe.decode(bytes, type: SMC.code("flt ")), 52.5)
    }

    func testDecodesIntelFixedPoint() {
        XCTAssertEqual(TemperatureProbe.decode([0x34, 0x80], type: SMC.code("sp78")), 52.5)
        XCTAssertEqual(TemperatureProbe.decode([0xFF, 0x00], type: SMC.code("sp78")), -1)
    }

    func testRejectsUnknownTypesAndShortData() {
        XCTAssertNil(TemperatureProbe.decode([1, 2, 3, 4], type: SMC.code("ui32")))
        XCTAssertNil(TemperatureProbe.decode([1], type: SMC.code("sp78")))
        XCTAssertFalse(TemperatureProbe.isPlausible(0))
        XCTAssertFalse(TemperatureProbe.isPlausible(200))
        XCTAssertTrue(TemperatureProbe.isPlausible(45))
    }

    func testPicksCPUSensorsForThisArchitecture() {
        #if arch(arm64)
            XCTAssertTrue(TemperatureProbe.isCPUSensor(SMC.code("Tp09")))
            XCTAssertTrue(TemperatureProbe.isCPUSensor(SMC.code("Te05")))
        #else
            XCTAssertTrue(TemperatureProbe.isCPUSensor(SMC.code("TC0P")))
        #endif
        XCTAssertFalse(TemperatureProbe.isCPUSensor(SMC.code("TB0T")))  // battery
        XCTAssertFalse(TemperatureProbe.isCPUSensor(SMC.code("F0Ac")))  // fan speed
    }

    func testPayloadMatchesTheCStructLayout() {
        var payload = SMC.Payload()
        payload.key = SMC.code("TC0P")
        payload.dataSize = 2
        payload.command = SMC.readKey
        payload.data32 = 7
        XCTAssertEqual(payload.raw.count, 80)
        XCTAssertEqual(Array(payload.raw[0..<4]), withUnsafeBytes(of: SMC.code("TC0P"), Array.init))
        XCTAssertEqual(payload.raw[28], 2)
        XCTAssertEqual(payload.raw[42], 5)
        XCTAssertEqual(payload.raw[44], 7)
    }

    /// Real sensors are missing in CI virtual machines, so this only checks the probe behaves.
    func testSampleIsNilOrPlausible() {
        let probe = TemperatureProbe()
        if let celsius = probe.sample() { XCTAssertTrue(TemperatureProbe.isPlausible(celsius)) }
    }
}
