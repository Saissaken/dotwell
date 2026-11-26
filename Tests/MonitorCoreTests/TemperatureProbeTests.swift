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

    func testDecodesIntelFanSpeeds() {
        // fpe2: 0x2138 >> 2 = 2126 rpm.
        XCTAssertEqual(TemperatureProbe.decode([0x21, 0x38], type: SMC.code("fpe2")), 2126)
        XCTAssertTrue(TemperatureProbe.isPlausibleRPM(0))
        XCTAssertTrue(TemperatureProbe.isPlausibleRPM(6500))
        XCTAssertFalse(TemperatureProbe.isPlausibleRPM(-1))
        XCTAssertFalse(TemperatureProbe.isPlausibleRPM(65_535))
    }

    /// CI virtual machines have no fans, so this only checks nothing is made up.
    func testFanSpeedIsNilOrPlausible() {
        if let rpm = TemperatureProbe().fanRPM() { XCTAssertTrue(TemperatureProbe.isPlausibleRPM(rpm)) }
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

    // MARK: - Apple silicon sensors

    func testNamesSensorFamilies() {
        XCTAssertEqual(HIDThermalSensors.Family(sensorName: "pACC MTR Temp Sensor2"), .cpuCluster)
        XCTAssertEqual(HIDThermalSensors.Family(sensorName: "eACC MTR Temp Sensor0"), .cpuCluster)
        XCTAssertEqual(HIDThermalSensors.Family(sensorName: "PMU tdie4"), .die)
        XCTAssertEqual(HIDThermalSensors.Family(sensorName: "SOC MTR Temp Sensor1"), .soc)
        XCTAssertNil(HIDThermalSensors.Family(sensorName: "GPU MTR Temp Sensor1"))
        XCTAssertNil(HIDThermalSensors.Family(sensorName: "PMU tdev3"))
        XCTAssertNil(HIDThermalSensors.Family(sensorName: "gas gauge battery"))
    }

    /// The case from btop on an M3 Max: core clusters at 44–45 °C while other die sensors run hotter.
    /// Only the cluster sensors count, so the hotter ones can't push the CPU temperature up.
    func testAveragesTheCoreClustersOnly() throws {
        let readings: [(name: String, celsius: Double)] = [
            ("pACC MTR Temp Sensor2", 44), ("pACC MTR Temp Sensor3", 45), ("pACC MTR Temp Sensor4", 45),
            ("eACC MTR Temp Sensor0", 44), ("PMU tdie1", 62), ("PMU tdie2", 64), ("SOC MTR Temp Sensor0", 58),
            ("GPU MTR Temp Sensor1", 70), ("gas gauge battery", 31),
        ]
        let celsius = try XCTUnwrap(HIDThermalSensors.cpuTemperature(readings))
        XCTAssertEqual(celsius, 44.5, accuracy: 0.001)
    }

    func testFallsBackToDieThenSoCSensors() {
        let die: [(name: String, celsius: Double)] = [
            ("PMU tdie1", 50), ("PMU tdie2", 54), ("SOC MTR Temp Sensor0", 70),
        ]
        XCTAssertEqual(HIDThermalSensors.cpuTemperature(die), 52)
        let soc: [(name: String, celsius: Double)] = [("SOC MTR Temp Sensor0", 40), ("SOC MTR Temp Sensor1", 42)]
        XCTAssertEqual(HIDThermalSensors.cpuTemperature(soc), 41)
    }

    func testIgnoresImplausibleReadings() {
        // A cluster sensor reading 0 or garbage must not hide the valid ones or drag the average down.
        let zero: [(name: String, celsius: Double)] = [("pACC MTR Temp Sensor2", 0), ("pACC MTR Temp Sensor3", 46)]
        XCTAssertEqual(HIDThermalSensors.cpuTemperature(zero), 46)
        XCTAssertEqual(HIDThermalSensors.cpuTemperature([("pACC MTR Temp Sensor2", -20), ("PMU tdie1", 48)]), 48)
        XCTAssertNil(HIDThermalSensors.cpuTemperature([("pACC MTR Temp Sensor2", 400)]))
        XCTAssertNil(HIDThermalSensors.cpuTemperature([]))
    }

    /// On an Apple silicon Mac with sensors, the reading must sit in a plausible range for a running CPU.
    /// CI virtual machines have no sensors, so there it only checks that nothing is made up.
    func testAppleSiliconSensorsReadPlausibly() {
        #if arch(arm64)
            let sensors = HIDThermalSensors()
            if let celsius = sensors.sample() {
                XCTAssertGreaterThan(celsius, 15)
                XCTAssertLessThan(celsius, 110)
                // Narrowed to one family after the first sample, the next reading stays close.
                if let again = sensors.sample() { XCTAssertEqual(again, celsius, accuracy: 15) }
            }
        #endif
    }

    /// Real sensors are missing in CI virtual machines, so this only checks the probe behaves.
    func testSampleIsNilOrPlausible() {
        let probe = TemperatureProbe()
        if let celsius = probe.sample() { XCTAssertTrue(TemperatureProbe.isPlausible(celsius)) }
    }
}
