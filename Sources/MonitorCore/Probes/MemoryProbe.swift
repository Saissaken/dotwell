import Darwin
import Foundation

/// macOS memory pressure as reported by the kernel (same signal Activity Monitor uses).
public enum MemoryPressure: Int, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4
}

public struct MemorySample: Equatable, Sendable {
    /// "Memory Used" as Activity Monitor defines it: app + wired + compressed.
    public var usedBytes: UInt64
    public var totalBytes: UInt64
    public var pressure: MemoryPressure

    public init(usedBytes: UInt64, totalBytes: UInt64, pressure: MemoryPressure) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.pressure = pressure
    }

    public var usedFraction: Float {
        totalBytes == 0 ? 0 : Float(Double(usedBytes) / Double(totalBytes))
    }
}

public final class MemoryProbe {
    private let host = mach_host_self()
    private let pageSize = UInt64(vm_kernel_page_size)
    private let total = ProcessInfo.processInfo.physicalMemory

    public init() {}

    public func sample() -> MemorySample? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let appPages = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return MemorySample(
            usedBytes: min(usedPages * pageSize, total), totalBytes: total, pressure: Self.readPressure())
    }

    static func readPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }
}
