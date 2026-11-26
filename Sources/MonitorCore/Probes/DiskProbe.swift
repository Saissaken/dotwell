import Foundation
import IOKit

public struct DiskSpace: Equatable, Sendable {
    public var availableBytes: UInt64
    public var totalBytes: UInt64

    public var freeFraction: Float {
        totalBytes == 0 ? 0 : Float(Double(availableBytes) / Double(totalBytes))
    }
}

public struct DiskIOCounters: Equatable, Sendable {
    public var bytesRead: UInt64
    public var bytesWritten: UInt64
}

public final class DiskProbe {
    private let root = URL(fileURLWithPath: "/")

    public init() {}

    /// Free space on the boot volume, counting purgeable space the way Finder does.
    public func space() -> DiskSpace? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? root.resourceValues(forKeys: keys),
            let available = values.volumeAvailableCapacityForImportantUsage,
            let total = values.volumeTotalCapacity
        else { return nil }
        return DiskSpace(availableBytes: UInt64(max(0, available)), totalBytes: UInt64(max(0, total)))
    }

    /// Cumulative bytes read/written across all block storage drivers.
    public func ioCounters() -> DiskIOCounters? {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
                == KERN_SUCCESS
        else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            {
                read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return DiskIOCounters(bytesRead: read, bytesWritten: written)
    }
}
