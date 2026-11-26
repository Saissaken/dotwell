import Foundation
import IOKit

public struct PowerSample: Equatable, Sendable {
    public enum Source: Equatable, Sendable { case battery, adapter }
    public var source: Source
    /// On battery: power drawn from the battery. On adapter: power entering the system (if the Mac reports it).
    public var watts: Double?
    public var isCharging: Bool
}

/// Reads the AppleSmartBattery IORegistry entry. Returns nil on Macs without a battery.
public final class PowerProbe {
    private var service: io_service_t

    public init() {
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    }

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    public var hasBattery: Bool { service != 0 }

    public func sample() -> PowerSample? {
        guard service != 0 else { return nil }
        let external = bool("ExternalConnected") ?? false
        let charging = bool("IsCharging") ?? false

        if external {
            var watts: Double?
            if let telemetry = property("PowerTelemetryData") as? [String: Any],
               let mw = (telemetry["SystemPowerIn"] as? NSNumber)?.doubleValue, mw > 0 {
                watts = mw / 1000
            }
            return PowerSample(source: .adapter, watts: watts, isCharging: charging)
        }

        guard let millivolts = number("Voltage")?.doubleValue,
              let milliamps = number("InstantAmperage")?.int64Value ?? number("Amperage")?.int64Value else {
            return PowerSample(source: .battery, watts: nil, isCharging: false)
        }
        let watts = Self.watts(millivolts: millivolts, milliamps: milliamps)
        return PowerSample(source: .battery, watts: watts, isCharging: false)
    }

    /// Amperage is negative while discharging; we report magnitude.
    static func watts(millivolts: Double, milliamps: Int64) -> Double {
        millivolts / 1000 * Double(milliamps.magnitude) / 1000
    }

    private func property(_ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private func number(_ key: String) -> NSNumber? { property(key) as? NSNumber }
    private func bool(_ key: String) -> Bool? { (property(key) as? NSNumber)?.boolValue }
}
