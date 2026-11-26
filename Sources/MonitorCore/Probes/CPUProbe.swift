import Darwin

/// Aggregate CPU ticks (user, system, idle, nice) as reported by the kernel.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }

    /// Fraction of busy time (0...1) between two readings. Handles 32-bit counter wrap.
    public static func usage(from old: CPUTicks, to new: CPUTicks) -> Float {
        let busy = UInt64(new.user &- old.user) + UInt64(new.system &- old.system) + UInt64(new.nice &- old.nice)
        let total = busy + UInt64(new.idle &- old.idle)
        guard total > 0 else { return 0 }
        return Float(Double(busy) / Double(total))
    }
}

/// Total CPU usage via a single `host_statistics(HOST_CPU_LOAD_INFO)` call.
public final class CPUProbe {
    private let host = mach_host_self()  // cached: each call to mach_host_self() takes a port right
    private var previous: CPUTicks?

    public init() {}

    /// Usage 0...1 since the previous call; nil on the first call or on error.
    public func sample() -> Float? {
        guard let now = readTicks() else { return nil }
        defer { previous = now }
        guard let previous else { return nil }
        return CPUTicks.usage(from: previous, to: now)
    }

    private func readTicks() -> CPUTicks? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = load.cpu_ticks
        return CPUTicks(user: t.0, system: t.1, idle: t.2, nice: t.3)
    }
}
