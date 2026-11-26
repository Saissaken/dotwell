import Darwin
import Foundation

/// CPU and memory used by one app (all of its processes) or by one standalone process.
public struct ProcessUsage: Sendable, Equatable, Identifiable {
    /// Bundle path for apps, executable path or name otherwise.
    public var id: String
    public var name: String
    /// `.app` bundle or executable path, used to look up the icon.
    public var path: String?
    /// Fraction of one core, like Activity Monitor's "% CPU" (1.5 = 150 %).
    public var cpu: Float
    /// Physical footprint, the "Memory" column of Activity Monitor.
    public var memoryBytes: UInt64

    public init(id: String, name: String, path: String?, cpu: Float, memoryBytes: UInt64) {
        self.id = id
        self.name = name
        self.path = path
        self.cpu = cpu
        self.memoryBytes = memoryBytes
    }
}

/// The heaviest apps right now. `byCPU` is empty until two samples exist.
public struct TopProcesses: Sendable, Equatable {
    public var byCPU: [ProcessUsage]
    public var byMemory: [ProcessUsage]

    public init(byCPU: [ProcessUsage] = [], byMemory: [ProcessUsage] = []) {
        self.byCPU = byCPU
        self.byMemory = byMemory
    }
}

/// Ranks apps by CPU and memory with `proc_pid_rusage`, one syscall per process.
///
/// Helper processes are grouped under the outermost `.app` bundle in their path, so Safari or Chrome
/// count as one entry. Without root, macOS only allows reading processes of the current user, so
/// system daemons such as `WindowServer` or `kernel_task` are not included.
///
/// Meant to run only while the popover is open; `reset()` drops all state when it closes.
public final class ProcessProbe {
    struct Group: Equatable {
        var id: String
        var name: String
        var path: String?

        var emptyUsage: ProcessUsage { ProcessUsage(id: id, name: name, path: path, cpu: 0, memoryBytes: 0) }
    }

    private struct Known {
        var startTime: UInt64
        var group: Group
    }

    private var known: [pid_t: Known] = [:]
    private var lastCPUNanos: [pid_t: UInt64] = [:]
    private var lastSampleNanos: UInt64?
    private var pids = [pid_t](repeating: 0, count: 1024)
    private let timebase: (numer: UInt64, denom: UInt64)

    public init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        timebase = info.denom == 0 ? (1, 1) : (UInt64(info.numer), UInt64(info.denom))
    }

    /// Nanoseconds since the last sample, or nil before the first one.
    public func elapsed(now: UInt64) -> UInt64? {
        lastSampleNanos.map { now &- $0 }
    }

    public func sample(now: UInt64 = DispatchTime.now().uptimeNanoseconds, limit: Int = 3) -> TopProcesses {
        let count = listPIDs()
        let elapsed = lastSampleNanos.map { now > $0 ? Double(now - $0) : 0 } ?? 0

        var usage: [String: ProcessUsage] = [:]
        var nextKnown: [pid_t: Known] = [:]
        var nextCPU: [pid_t: UInt64] = [:]
        nextKnown.reserveCapacity(count)
        nextCPU.reserveCapacity(count)

        for pid in pids.prefix(count) where pid > 0 {
            guard let info = Self.rusage(pid) else { continue }
            let cpuNanos = (info.ri_user_time &+ info.ri_system_time) &* timebase.numer / timebase.denom

            let group: Group
            if let cached = known[pid], cached.startTime == info.ri_proc_start_abstime {
                group = cached.group
            } else {
                group = Self.group(pid: pid)
            }
            nextKnown[pid] = Known(startTime: info.ri_proc_start_abstime, group: group)
            nextCPU[pid] = cpuNanos

            var cpu: Float = 0
            if elapsed > 0, let previous = lastCPUNanos[pid], cpuNanos >= previous,
                known[pid]?.startTime == info.ri_proc_start_abstime
            {
                cpu = Float(Double(cpuNanos - previous) / elapsed)
            }
            var entry = usage[group.id] ?? group.emptyUsage
            entry.cpu += cpu
            entry.memoryBytes &+= info.ri_phys_footprint
            usage[group.id] = entry
        }

        let hadBaseline = elapsed > 0
        known = nextKnown
        lastCPUNanos = nextCPU
        lastSampleNanos = now

        let all = Array(usage.values)
        return TopProcesses(
            byCPU: hadBaseline ? Self.top(all, limit: limit, by: \.cpu, minimum: 0.001) : [],
            byMemory: Self.top(all, limit: limit, by: \.memoryBytes, minimum: 1))
    }

    public func reset() {
        known = [:]
        lastCPUNanos = [:]
        lastSampleNanos = nil
    }

    // MARK: - Helpers

    /// The `limit` largest entries by `key`, ignoring those below `minimum`. Ties break by name for stable order.
    static func top<Value: Comparable>(
        _ entries: [ProcessUsage], limit: Int, by key: KeyPath<ProcessUsage, Value>, minimum: Value
    ) -> [ProcessUsage] {
        let sorted = entries.filter { $0[keyPath: key] >= minimum }.sorted {
            $0[keyPath: key] != $1[keyPath: key] ? $0[keyPath: key] > $1[keyPath: key] : $0.name < $1.name
        }
        return Array(sorted.prefix(limit))
    }

    /// Fills `pids` and returns how many are valid, growing the buffer if the system has more processes.
    private func listPIDs() -> Int {
        while true {
            let size = Int32(pids.count * MemoryLayout<pid_t>.stride)
            let count = Int(pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, size) })
            if count <= 0 { return 0 }
            if count < pids.count { return count }
            pids = [pid_t](repeating: 0, count: pids.count * 2)
        }
    }

    private static func rusage(_ pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info : nil
    }

    static func group(pid: pid_t) -> Group {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))  // PROC_PIDPATHINFO_MAXSIZE
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            return group(executablePath: string(buffer))
        }
        var name = [CChar](repeating: 0, count: 64)
        proc_name(pid, &name, UInt32(name.count))
        let text = string(name)
        if text.isEmpty { return Group(id: "pid:\(pid)", name: "Process \(pid)", path: nil) }
        return Group(id: "name:\(text)", name: text, path: nil)
    }

    private static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Groups an executable under the outermost app bundle in its path, if any.
    static func group(executablePath path: String) -> Group {
        if let range = path.range(of: ".app/") {
            let bundle = String(path[..<range.lowerBound]) + ".app"
            let name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
            return Group(id: bundle, name: name, path: bundle)
        }
        let name = (path as NSString).lastPathComponent
        return Group(id: path, name: name.isEmpty ? path : name, path: path)
    }
}
