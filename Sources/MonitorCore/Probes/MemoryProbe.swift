import Darwin
import Foundation

/// macOS memory pressure as reported by the kernel (same signal Activity Monitor uses).
public enum MemoryPressure: Int, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4
}

public struct MemorySample: Equatable, Sendable {
    /// "Memory Used" as Activity Monitor defines it; see `VMPageCounts.usedBytes`.
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

/// The `vm_statistics64` page counts that Activity Monitor's memory figures are built from.
struct VMPageCounts: Equatable {
    var free: UInt64
    var internal: UInt64
    var external: UInt64
    var purgeable: UInt64
    var wired: UInt64
    var compressor: UInt64

    /// Activity Monitor's "Memory Used": physical memory minus free pages and "Cached Files"
    /// (file-backed plus purgeable pages).
    ///
    /// Summing "App Memory" (internal − purgeable), "Wired" and "Compressed" falls short of it on
    /// Apple Silicon, because some physical memory (for example GPU and firmware reservations) is not
    /// in any page queue. Counting down from the physical total includes that memory, as Activity
    /// Monitor does. The sum is kept as a floor in case the page counts are briefly inconsistent.
    func usedBytes(pageSize: UInt64, totalBytes: UInt64) -> UInt64 {
        let appPages = internal > purgeable ? internal - purgeable : 0
        let floor = (appPages + wired + compressor) * pageSize
        let available = (free + external + purgeable) * pageSize
        let counted = totalBytes > available ? totalBytes - available : 0
        return min(max(counted, floor), totalBytes)
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
        let pages = VMPageCounts(
            free: UInt64(stats.free_count), internal: UInt64(stats.internal_page_count),
            external: UInt64(stats.external_page_count), purgeable: UInt64(stats.purgeable_count),
            wired: UInt64(stats.wire_count), compressor: UInt64(stats.compressor_page_count))
        return MemorySample(
            usedBytes: pages.usedBytes(pageSize: pageSize, totalBytes: total), totalBytes: total,
            pressure: Self.readPressure())
    }

    static func readPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }
}
