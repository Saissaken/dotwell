import CoreFoundation
import Darwin

/// CPU or GPU temperature on Apple silicon from the thermal sensors macOS publishes through `IOHIDEventSystem`.
///
/// Unlike SMC keys, whose meaning changes between chips (on M3, `Tp*` keys are not the CPU cores), these
/// sensors carry descriptive names: `pACC MTR Temp Sensor*` and `eACC MTR Temp Sensor*` sit on the
/// performance and efficiency core clusters. The probe averages them, falling back to the `PMU tdie*` die
/// sensors and then to the `SOC MTR Temp Sensor*` ones on chips without cluster sensors. This is the same
/// choice btop makes, so both tools agree.
///
/// For the GPU it averages the `GPU MTR Temp Sensor*` sensors. Chips that don't publish them get no GPU
/// temperature rather than a guess from another sensor.
///
/// The `IOHIDEventSystemClient` functions are not in the public headers, so they are looked up at runtime;
/// when any is missing the reader finds no sensors and the caller falls back to the SMC.
final class HIDThermalSensors {
    /// The part of the chip whose temperature is read.
    enum Part {
        case cpu, gpu
    }

    static func isGPUSensor(_ name: String) -> Bool { name.hasPrefix("GPU MTR Temp Sensor") }

    /// Average of the plausible GPU sensor readings, or nil.
    static func gpuTemperature(_ readings: [(name: String, celsius: Double)]) -> Double? {
        let values = readings.filter { isGPUSensor($0.name) && $0.celsius > 0 && $0.celsius < 150 }.map(\.celsius)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Sensor families in order of preference.
    enum Family: Int, CaseIterable {
        case cpuCluster  // pACC / eACC
        case die  // PMU tdie
        case soc  // SOC MTR

        init?(sensorName name: String) {
            if name.hasPrefix("pACC") || name.hasPrefix("eACC") {
                self = .cpuCluster
            } else if name.hasPrefix("PMU tdie") {
                self = .die
            } else if name.hasPrefix("SOC MTR Temp Sensor") {
                self = .soc
            } else {
                return nil
            }
        }
    }

    /// Average of the readings from the most preferred family that has a plausible reading, or nil.
    static func cpuTemperature(_ readings: [(name: String, celsius: Double)]) -> Double? {
        cpuReading(readings)?.celsius
    }

    static func cpuReading(_ readings: [(name: String, celsius: Double)]) -> (family: Family, celsius: Double)? {
        var byFamily: [Family: [Double]] = [:]
        for reading in readings where reading.celsius > 0 && reading.celsius < 150 {
            guard let family = Family(sensorName: reading.name) else { continue }
            byFamily[family, default: []].append(reading.celsius)
        }
        for family in Family.allCases {
            if let values = byFamily[family], !values.isEmpty {
                return (family, values.reduce(0, +) / Double(values.count))
            }
        }
        return nil
    }

    // MARK: - IOHIDEventSystemClient

    private typealias ClientCreate = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias ClientSetMatching = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Int32
    private typealias ClientCopyServices = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    private typealias ServiceCopyProperty = @convention(c) (UnsafeRawPointer, CFString) -> UnsafeMutableRawPointer?
    private typealias ServiceCopyEvent =
        @convention(c) (UnsafeRawPointer, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    private typealias EventGetFloatValue = @convention(c) (UnsafeMutableRawPointer, Int32) -> Double

    private struct API {
        var create: ClientCreate
        var setMatching: ClientSetMatching
        var copyServices: ClientCopyServices
        var copyProperty: ServiceCopyProperty
        var copyEvent: ServiceCopyEvent
        var floatValue: EventGetFloatValue

        static func load() -> API? {
            guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
                return nil
            }
            func symbol<T>(_ name: String, as _: T.Type) -> T? {
                dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
            }
            guard let create = symbol("IOHIDEventSystemClientCreate", as: ClientCreate.self),
                let setMatching = symbol("IOHIDEventSystemClientSetMatching", as: ClientSetMatching.self),
                let copyServices = symbol("IOHIDEventSystemClientCopyServices", as: ClientCopyServices.self),
                let copyProperty = symbol("IOHIDServiceClientCopyProperty", as: ServiceCopyProperty.self),
                let copyEvent = symbol("IOHIDServiceClientCopyEvent", as: ServiceCopyEvent.self),
                let floatValue = symbol("IOHIDEventGetFloatValue", as: EventGetFloatValue.self)
            else { return nil }
            return API(
                create: create, setMatching: setMatching, copyServices: copyServices, copyProperty: copyProperty,
                copyEvent: copyEvent, floatValue: floatValue)
        }
    }

    private static let temperatureEvent: Int64 = 15  // kIOHIDEventTypeTemperature
    private static let temperatureField = Int32(temperatureEvent << 16)  // IOHIDEventFieldBase(type)

    private let api: API?
    private var client: UnsafeMutableRawPointer?
    private var services: CFArray?  // keeps the service clients below alive
    private var sensors: [(name: String, service: UnsafeRawPointer)] = []
    private var discovered = false
    private var narrowed = false
    private let part: Part

    init(_ part: Part = .cpu) {
        self.part = part
        api = API.load()
    }

    deinit {
        if let client { Unmanaged<AnyObject>.fromOpaque(client).release() }
    }

    /// Current temperature of `part` in °C, or nil when the Mac has no such sensors (Intel, virtual machines).
    func sample() -> Double? {
        if !discovered { discover() }
        guard let api, !sensors.isEmpty else { return nil }
        let readings = sensors.compactMap { sensor -> (name: String, celsius: Double)? in
            guard let event = api.copyEvent(sensor.service, Self.temperatureEvent, 0, 0) else { return nil }
            defer { Unmanaged<AnyObject>.fromOpaque(event).release() }
            return (sensor.name, api.floatValue(event, Self.temperatureField))
        }
        if part == .gpu { return Self.gpuTemperature(readings) }
        guard let result = Self.cpuReading(readings) else { return nil }
        if !narrowed {
            // Later samples only read the family in use, to keep each sample cheap.
            narrowed = true
            sensors.removeAll { Family(sensorName: $0.name) != result.family }
        }
        return result.celsius
    }

    /// Lists the thermal sensors once and keeps the ones `part` can use.
    private func discover() {
        discovered = true
        guard let api, let client = api.create(kCFAllocatorDefault) else { return }
        self.client = client
        // Apple vendor usage page 0xff00, usage 5: temperature sensors.
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = api.setMatching(client, matching)
        guard let raw = api.copyServices(client) else { return }
        let services = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue()
        self.services = services
        for index in 0..<CFArrayGetCount(services) {
            guard let service = CFArrayGetValueAtIndex(services, index),
                let property = api.copyProperty(service, "Product" as CFString)
            else { continue }
            let value = Unmanaged<AnyObject>.fromOpaque(property).takeRetainedValue()
            guard let name = value as? String else { continue }
            if part == .gpu ? Self.isGPUSensor(name) : Family(sensorName: name) != nil {
                sensors.append((name, service))
            }
        }
    }
}
