import Foundation
import IOKit

/// What the GPU is doing right now. Readings the Mac doesn't provide stay nil.
public struct GPUSample: Sendable, Equatable {
    /// Fraction of time the GPU was busy, 0...1, as its driver reports it.
    public var utilization: Float?
    public var coreCount: Int?
    /// Power drawn by the GPU, in watts.
    public var watts: Double?
    /// Average of the GPU's own temperature sensors, in °C.
    public var temperature: Float?

    public init(utilization: Float? = nil, coreCount: Int? = nil, watts: Double? = nil, temperature: Float? = nil) {
        self.utilization = utilization
        self.coreCount = coreCount
        self.watts = watts
        self.temperature = temperature
    }
}

/// Reads the Apple silicon GPU, without root.
///
/// - Use: the `Device Utilization %` the GPU driver publishes in its `PerformanceStatistics` registry
///   property, one IOKit call.
/// - Per app: the driver keeps one user client per process that uses the GPU, as a child of the accelerator
///   in the I/O Registry. Each names its process in `IOUserClientCreator` ("pid 412, Safari") and adds up
///   the GPU time it used, in nanoseconds, in `AppUsage`. Differences between two samples give each app's
///   share of the GPU, like the "% GPU" column of Activity Monitor.
/// - Power: see `GPUEnergyReader`. Temperature: see `HIDThermalSensors`.
///
/// Intel Macs are not supported: their GPU drivers publish different statistics. The probe is meant to run
/// only while the popover is open.
public final class GPUProbe {
    private var accelerator: io_registry_entry_t = 0
    public let coreCount: Int?
    private let energy = GPUEnergyReader()
    private lazy var thermal = HIDThermalSensors(.gpu)

    public init() {
        #if arch(arm64)
            accelerator = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        #endif
        coreCount = accelerator == 0 ? nil : Self.integer(accelerator, "gpu-core-count")
    }

    deinit {
        if accelerator != 0 { IOObjectRelease(accelerator) }
    }

    /// False on Macs without an Apple silicon GPU the probe can read.
    public var isAvailable: Bool { accelerator != 0 }

    /// The fraction of time the GPU was busy, 0...1.
    public func utilization() -> Float? {
        guard accelerator != 0,
            let raw = IORegistryEntryCreateCFProperty(
                accelerator, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
            let statistics = raw as? [String: Any]
        else { return nil }
        return Self.utilization(fromStatistics: statistics)
    }

    /// GPU watts since the previous call, nil on the first call or where macOS doesn't report it.
    public func watts(now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Double? {
        accelerator == 0 ? nil : energy.watts(now: now)
    }

    public func temperature() -> Float? {
        accelerator == 0 ? nil : thermal.sample().map(Float.init)
    }

    /// Total GPU time each process has used so far, in nanoseconds.
    public func processGPUTimes() -> [pid_t: UInt64] {
        guard accelerator != 0 else { return [:] }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }
        var times: [pid_t: UInt64] = [:]
        while true {
            let client = IOIteratorNext(iterator)
            if client == 0 { break }
            defer { IOObjectRelease(client) }
            guard let creator = Self.property(client, "IOUserClientCreator") as? String,
                let pid = Self.pid(fromCreator: creator)
            else { continue }
            times[pid, default: 0] &+= Self.gpuTime(fromAppUsage: Self.property(client, "AppUsage"))
        }
        return times
    }

    /// Forgets the power reading, so the next one starts a new interval.
    public func reset() {
        energy.reset()
    }

    // MARK: - Parsing

    static func utilization(fromStatistics statistics: [String: Any]) -> Float? {
        guard let percent = (statistics["Device Utilization %"] as? NSNumber)?.doubleValue else { return nil }
        return Float(min(max(percent, 0), 100) / 100)
    }

    /// "pid 412, Safari" -> 412.
    static func pid(fromCreator creator: String) -> pid_t? {
        guard creator.hasPrefix("pid ") else { return nil }
        return pid_t(creator.dropFirst(4).prefix { $0.isNumber })
    }

    /// Sum of `accumulatedGPUTime` over the entries of an `AppUsage` array (one per graphics API in use).
    static func gpuTime(fromAppUsage value: Any?) -> UInt64 {
        guard let entries = value as? [[String: Any]] else { return 0 }
        return entries.reduce(UInt64(0)) { total, entry in
            total &+ ((entry["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0)
        }
    }

    // MARK: - Registry

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func integer(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        (property(entry, key) as? NSNumber)?.intValue
    }
}
