import Foundation
import IOKit

/// Reads the CPU temperature.
///
/// On Apple silicon it comes from the CPU cluster sensors macOS names itself (see `HIDThermalSensors`).
/// Intel Macs, and Apple silicon Macs where those sensors can't be read, use the System Management
/// Controller (SMC) instead.
///
/// The SMC is reached through the `AppleSMC` IOKit user client, which needs neither root nor entitlements
/// (it is unavailable inside the App Sandbox). Sensor keys differ between chips, so instead of a per-model
/// table the probe lists the SMC keys once and keeps the CPU sensors: `Tp*` and `Te*` (floats, Apple silicon
/// performance and efficiency cores) or `TC*` (fixed point, Intel). Sensors that read an implausible value
/// at discovery are dropped. Each sample then costs one IOKit call per sensor.
///
/// Returns nil when no sensor is found, for example in a virtual machine.
public final class TemperatureProbe {
    struct Sensor: Equatable {
        var key: UInt32
        var size: UInt32
        var type: UInt32
    }

    private var connection: io_connect_t = 0
    private var sensors: [Sensor]?  // nil until discovered
    private var fans: [Sensor]?  // nil until discovered, empty on fanless Macs
    #if arch(arm64)
        private let hid = HIDThermalSensors()
    #endif

    public init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// Average CPU temperature in degrees Celsius.
    public func sample() -> Float? {
        #if arch(arm64)
            if let celsius = hid.sample() { return Float(celsius) }
        #endif
        return sampleSMC()
    }

    private func sampleSMC() -> Float? {
        guard connection != 0 else { return nil }
        if sensors == nil { sensors = discover() }
        guard let sensors, !sensors.isEmpty else { return nil }
        var sum: Float = 0
        var count = 0
        for sensor in sensors {
            guard let value = read(sensor), Self.isPlausible(value) else { continue }
            sum += value
            count += 1
        }
        return count > 0 ? sum / Float(count) : nil
    }

    /// Average speed of the fans in RPM, 0 while they're stopped. Nil on fanless Macs (MacBook Air) and
    /// where the SMC can't be read.
    public func fanRPM() -> Double? {
        guard connection != 0 else { return nil }
        if fans == nil { fans = discoverFans() }
        guard let fans, !fans.isEmpty else { return nil }
        let speeds = fans.compactMap { read($0) }.map(Double.init).filter(Self.isPlausibleRPM)
        return speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)
    }

    static func isPlausibleRPM(_ rpm: Double) -> Bool { rpm >= 0 && rpm < 15_000 }

    /// `FNum` holds the number of fans, `F<n>Ac` the current speed of fan n.
    private func discoverFans() -> [Sensor] {
        let countKey = SMC.code("FNum")
        guard let info = keyInfo(countKey), let bytes = read(countKey, size: info.size), let count = bytes.first
        else { return [] }
        return (0..<min(Int(count), 9)).compactMap { index in
            let key = SMC.code("F\(index)Ac")
            guard let info = keyInfo(key) else { return nil }
            return Sensor(key: key, size: info.size, type: info.type)
        }
    }

    // MARK: - Discovery

    private func discover() -> [Sensor] {
        let countKey = SMC.code("#KEY")
        guard let info = keyInfo(countKey), let bytes = read(countKey, size: info.size), bytes.count >= 4 else {
            return []
        }
        let count = bytes.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }

        var found: [Sensor] = []
        for index in 0..<min(count, 8192) {
            guard let key = key(at: index), Self.isCPUSensor(key), let info = keyInfo(key) else { continue }
            let sensor = Sensor(key: key, size: info.size, type: info.type)
            if let value = read(sensor), value > 10, value < 120 { found.append(sensor) }
        }
        return found
    }

    /// CPU die sensors for the architecture this build runs on.
    static func isCPUSensor(_ key: UInt32) -> Bool {
        let prefix = key >> 16
        #if arch(arm64)
            return prefix == SMC.code("Tp") || prefix == SMC.code("Te")
        #else
            return prefix == SMC.code("TC")
        #endif
    }

    static func isPlausible(_ celsius: Float) -> Bool { celsius > 0 && celsius < 150 }

    // MARK: - Decoding

    static func decode(_ bytes: [UInt8], type: UInt32) -> Float? {
        switch type {
        case SMC.code("flt ") where bytes.count >= 4:
            // Native (little-endian) IEEE 754 float.
            let bits = bytes.prefix(4).reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            let value = Float(bitPattern: bits)
            return value.isFinite ? value : nil
        case SMC.code("fpe2") where bytes.count >= 2:
            // Big-endian unsigned fixed point with 2 fractional bits (Intel fan speeds).
            return Float(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case SMC.code("sp78") where bytes.count >= 2:
            // Big-endian signed fixed point with 8 fractional bits.
            return Float(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }

    // MARK: - SMC calls

    private func read(_ sensor: Sensor) -> Float? {
        read(sensor.key, size: sensor.size).flatMap { Self.decode($0, type: sensor.type) }
    }

    private func key(at index: UInt32) -> UInt32? {
        var input = SMC.Payload()
        input.command = SMC.getKeyFromIndex
        input.data32 = index
        return call(input)?.key
    }

    private func keyInfo(_ key: UInt32) -> (size: UInt32, type: UInt32)? {
        var input = SMC.Payload()
        input.key = key
        input.command = SMC.getKeyInfo
        guard let output = call(input) else { return nil }
        return (output.dataSize, output.dataType)
    }

    private func read(_ key: UInt32, size: UInt32) -> [UInt8]? {
        var input = SMC.Payload()
        input.key = key
        input.dataSize = size
        input.command = SMC.readKey
        return call(input)?.bytes(count: Int(min(size, 32)))
    }

    private func call(_ input: SMC.Payload) -> SMC.Payload? {
        var output = SMC.Payload()
        var outputSize = SMC.Payload.size
        let result = input.raw.withUnsafeBytes { inBytes in
            output.raw.withUnsafeMutableBytes { outBytes in
                IOConnectCallStructMethod(
                    connection, SMC.handleEvent, inBytes.baseAddress, SMC.Payload.size, outBytes.baseAddress,
                    &outputSize)
            }
        }
        guard result == KERN_SUCCESS, output.result == 0 else { return nil }
        return output
    }
}

/// The `AppleSMC` user client protocol: one 80-byte `SMCKeyData_t` struct in and out.
enum SMC {
    static let handleEvent: UInt32 = 2
    static let readKey: UInt8 = 5
    static let getKeyFromIndex: UInt8 = 8
    static let getKeyInfo: UInt8 = 9

    /// Four-character code as the SMC stores it, e.g. `"TC0P"`.
    static func code(_ text: String) -> UInt32 {
        text.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }

    /// `SMCKeyData_t`, kept as raw bytes at the C struct's offsets so the layout cannot drift.
    struct Payload {
        static let size = 80
        var raw = [UInt8](repeating: 0, count: size)

        var key: UInt32 {
            get { load(0) }
            set { store(newValue, at: 0) }
        }
        var dataSize: UInt32 {
            get { load(28) }
            set { store(newValue, at: 28) }
        }
        var dataType: UInt32 { load(32) }
        var result: UInt8 { raw[40] }
        var command: UInt8 {
            get { raw[42] }
            set { raw[42] = newValue }
        }
        var data32: UInt32 {
            get { load(44) }
            set { store(newValue, at: 44) }
        }
        func bytes(count: Int) -> [UInt8] { Array(raw[48..<48 + count]) }

        private func load(_ offset: Int) -> UInt32 {
            raw.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        }

        private mutating func store(_ value: UInt32, at offset: Int) {
            raw.withUnsafeMutableBytes { $0.storeBytes(of: value, toByteOffset: offset, as: UInt32.self) }
        }
    }
}
