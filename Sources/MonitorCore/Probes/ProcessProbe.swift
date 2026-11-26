import Darwin
import Foundation

/// Resources used by one app (all of its processes) or by one standalone process.
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
    /// Bytes read plus written per second.
    public var diskBytesPerSec: Double
    /// Energy the kernel attributes to the app, in watts. Zero where macOS doesn't report it.
    public var watts: Double
    /// The app's main process: the bundle's own executable when it runs, otherwise the oldest process.
    /// This is the one to quit or `kill` to stop the app.
    public var pid: pid_t
    /// How many processes were added up in this entry.
    public var processCount: Int

    public init(
        id: String, name: String, path: String?, cpu: Float = 0, memoryBytes: UInt64 = 0,
        diskBytesPerSec: Double = 0, watts: Double = 0, pid: pid_t = 0, processCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.cpu = cpu
        self.memoryBytes = memoryBytes
        self.diskBytesPerSec = diskBytesPerSec
        self.watts = watts
        self.pid = pid
        self.processCount = processCount
    }
}

/// The apps using the most of each resource right now, largest first, at most `limit` each.
/// Rates (CPU, disk, power) need two samples, so those lists are empty right after the first one;
/// any list is also empty when nothing uses that resource.
public struct TopApps: Sendable, Equatable {
    /// How many apps each list keeps.
    public static let limit = 5

    public var byCPU: [ProcessUsage]
    public var byMemory: [ProcessUsage]
    public var byDisk: [ProcessUsage]
    public var byPower: [ProcessUsage]
    /// False until a second sample makes rates available.
    public var hasRates: Bool

    public var cpu: ProcessUsage? { byCPU.first }
    public var memory: ProcessUsage? { byMemory.first }
    public var disk: ProcessUsage? { byDisk.first }
    public var power: ProcessUsage? { byPower.first }

    public init(
        byCPU: [ProcessUsage] = [], byMemory: [ProcessUsage] = [], byDisk: [ProcessUsage] = [],
        byPower: [ProcessUsage] = [], hasRates: Bool = true
    ) {
        self.byCPU = byCPU
        self.byMemory = byMemory
        self.byDisk = byDisk
        self.byPower = byPower
        self.hasRates = hasRates
    }
}

/// Finds the apps using the most CPU, memory, disk I/O and energy with `proc_pid_rusage`,
/// one syscall per process.
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
        /// The process runs the app bundle's own executable (`X.app/Contents/MacOS/…`), not a helper.
        var isMain = false

        var emptyUsage: ProcessUsage { ProcessUsage(id: id, name: name, path: path) }
    }

    /// Picks an app's main process: its own executable first, then the oldest process.
    struct Leader {
        var pid: pid_t
        var isMain: Bool
        var startTime: UInt64

        func leads(_ other: Leader) -> Bool {
            if isMain != other.isMain { return isMain }
            if startTime != other.startTime { return startTime < other.startTime }
            return pid < other.pid
        }
    }

    private struct Known {
        var startTime: UInt64
        var group: Group
    }

    /// Cumulative per-process counters, diffed between samples.
    private struct Counters {
        var startTime: UInt64
        var cpuNanos: UInt64
        var diskBytes: UInt64
        var energyNanojoules: UInt64
    }

    private var known: [pid_t: Known] = [:]
    private var last: [pid_t: Counters] = [:]
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

    public func sample(now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> TopApps {
        let (all, hasRates) = usage(now: now)
        let limit = TopApps.limit
        guard hasRates else {
            return TopApps(byMemory: Self.ranked(all, by: \.memoryBytes, minimum: 1, limit: limit), hasRates: false)
        }
        return TopApps(
            byCPU: Self.ranked(all, by: \.cpu, minimum: 0.001, limit: limit),
            byMemory: Self.ranked(all, by: \.memoryBytes, minimum: 1, limit: limit),
            byDisk: Self.ranked(all, by: \.diskBytesPerSec, minimum: 1024, limit: limit),
            byPower: Self.ranked(all, by: \.watts, minimum: 0.01, limit: limit))
    }

    /// Usage of every readable app. Rates stay zero on the first call (`hasRates == false`).
    func usage(now: UInt64) -> (apps: [ProcessUsage], hasRates: Bool) {
        let count = listPIDs()
        let elapsed = lastSampleNanos.map { now > $0 ? Double(now - $0) : 0 } ?? 0

        var usage: [String: ProcessUsage] = [:]
        /// Per app, the process that best stands for it so far.
        var leaders: [String: Leader] = [:]
        var nextKnown: [pid_t: Known] = [:]
        var next: [pid_t: Counters] = [:]
        nextKnown.reserveCapacity(count)
        next.reserveCapacity(count)

        for pid in pids.prefix(count) where pid > 0 {
            guard let info = Self.rusage(pid) else { continue }
            let start = info.ri_proc_start_abstime
            let counters = Counters(
                startTime: start,
                cpuNanos: (info.ri_user_time &+ info.ri_system_time) &* timebase.numer / timebase.denom,
                diskBytes: info.ri_diskio_bytesread &+ info.ri_diskio_byteswritten,
                energyNanojoules: info.ri_energy_nj)

            let group: Group
            if let cached = known[pid], cached.startTime == start {
                group = cached.group
            } else {
                group = Self.group(pid: pid)
            }
            nextKnown[pid] = Known(startTime: start, group: group)
            next[pid] = counters

            var entry = usage[group.id] ?? group.emptyUsage
            entry.processCount += 1
            let candidate = Leader(pid: pid, isMain: group.isMain, startTime: start)
            if leaders[group.id].map({ candidate.leads($0) }) ?? true {
                leaders[group.id] = candidate
                entry.pid = pid
            }
            entry.memoryBytes &+= info.ri_phys_footprint
            if elapsed > 0, let previous = last[pid], previous.startTime == start {
                entry.cpu += Float(Self.delta(previous.cpuNanos, counters.cpuNanos) / elapsed)
                entry.diskBytesPerSec += Self.delta(previous.diskBytes, counters.diskBytes) / (elapsed / 1e9)
                // nJ per ns is J per s.
                entry.watts += Self.delta(previous.energyNanojoules, counters.energyNanojoules) / elapsed
            }
            usage[group.id] = entry
        }

        let hasRates = elapsed > 0
        known = nextKnown
        last = next
        lastSampleNanos = now

        return (Array(usage.values), hasRates)
    }

    public func reset() {
        known = [:]
        last = [:]
        lastSampleNanos = nil
    }

    // MARK: - Helpers

    /// The `limit` entries with the largest `key`, largest first, ignoring those below `minimum`.
    /// Ties break by name for a stable order.
    static func ranked<Value: Comparable>(
        _ entries: [ProcessUsage], by key: KeyPath<ProcessUsage, Value>, minimum: Value, limit: Int
    ) -> [ProcessUsage] {
        let sorted = entries.filter { $0[keyPath: key] >= minimum }.sorted {
            $0[keyPath: key] != $1[keyPath: key] ? $0[keyPath: key] > $1[keyPath: key] : $0.name < $1.name
        }
        return Array(sorted.prefix(limit))
    }

    private static func delta(_ old: UInt64, _ new: UInt64) -> Double {
        new >= old ? Double(new - old) : 0
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

    /// V6 (macOS 12+) adds `ri_energy_nj`.
    private static func rusage(_ pid: pid_t) -> rusage_info_v6? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
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
            let inner = path[range.upperBound...]
            let isMain = inner.hasPrefix("Contents/MacOS/") && !inner.dropFirst(15).contains("/")
            return Group(id: bundle, name: name, path: bundle, isMain: isMain)
        }
        let name = (path as NSString).lastPathComponent
        return Group(id: path, name: name.isEmpty ? path : name, path: path)
    }
}
