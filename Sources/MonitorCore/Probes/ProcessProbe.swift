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
    /// Share of the GPU's time, like Activity Monitor's "% GPU" (1 = 100 %).
    public var gpu: Float

    public init(
        id: String, name: String, path: String?, cpu: Float = 0, memoryBytes: UInt64 = 0,
        diskBytesPerSec: Double = 0, watts: Double = 0, gpu: Float = 0
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.cpu = cpu
        self.memoryBytes = memoryBytes
        self.diskBytesPerSec = diskBytesPerSec
        self.watts = watts
        self.gpu = gpu
    }
}

/// The app using the most of each resource right now. Rates (CPU, disk, power) need two samples,
/// so they are nil right after the first one; any of them is also nil when nothing uses that resource.
public struct TopApps: Sendable, Equatable {
    public var cpu: ProcessUsage?
    public var memory: ProcessUsage?
    public var disk: ProcessUsage?
    public var power: ProcessUsage?
    public var gpu: ProcessUsage?
    /// False until a second sample makes rates available.
    public var hasRates: Bool

    public init(
        cpu: ProcessUsage? = nil, memory: ProcessUsage? = nil, disk: ProcessUsage? = nil,
        power: ProcessUsage? = nil, gpu: ProcessUsage? = nil, hasRates: Bool = true
    ) {
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
        self.power = power
        self.gpu = gpu
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

        var emptyUsage: ProcessUsage { ProcessUsage(id: id, name: name, path: path) }
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
    /// GPU time per process at the last sample, in nanoseconds.
    private var lastGPU: [pid_t: UInt64] = [:]
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

    /// - Parameter gpuTimes: each process's total GPU time so far (`GPUProbe.processGPUTimes()`), or nil to
    ///   skip the GPU.
    public func sample(
        now: UInt64 = DispatchTime.now().uptimeNanoseconds, gpuTimes: [pid_t: UInt64]? = nil
    ) -> TopApps {
        let (all, hasRates) = usage(now: now, gpuTimes: gpuTimes)
        guard hasRates else {
            return TopApps(memory: Self.top(all, by: \.memoryBytes, minimum: 1), hasRates: false)
        }
        return TopApps(
            cpu: Self.top(all, by: \.cpu, minimum: 0.001),
            memory: Self.top(all, by: \.memoryBytes, minimum: 1),
            disk: Self.top(all, by: \.diskBytesPerSec, minimum: 1024),
            power: Self.top(all, by: \.watts, minimum: 0.01),
            gpu: Self.top(all, by: \.gpu, minimum: 0.001))
    }

    /// Usage of every readable app. Rates stay zero on the first call (`hasRates == false`).
    func usage(now: UInt64, gpuTimes: [pid_t: UInt64]? = nil) -> (apps: [ProcessUsage], hasRates: Bool) {
        let count = listPIDs()
        let elapsed = lastSampleNanos.map { now > $0 ? Double(now - $0) : 0 } ?? 0

        var usage: [String: ProcessUsage] = [:]
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
            entry.memoryBytes &+= info.ri_phys_footprint
            if elapsed > 0, let previous = last[pid], previous.startTime == start {
                entry.cpu += Float(Self.delta(previous.cpuNanos, counters.cpuNanos) / elapsed)
                entry.diskBytesPerSec += Self.delta(previous.diskBytes, counters.diskBytes) / (elapsed / 1e9)
                // nJ per ns is J per s.
                entry.watts += Self.delta(previous.energyNanojoules, counters.energyNanojoules) / elapsed
            }
            usage[group.id] = entry
        }

        // GPU time also comes from processes this user can't read with proc_pid_rusage, such as WindowServer.
        if let gpuTimes {
            for (pid, nanos) in gpuTimes {
                guard elapsed > 0, let previous = lastGPU[pid], nanos > previous else { continue }
                let group = nextKnown[pid]?.group ?? Self.group(pid: pid)
                var entry = usage[group.id] ?? group.emptyUsage
                entry.gpu += Float(Double(nanos - previous) / elapsed)
                usage[group.id] = entry
            }
            lastGPU = gpuTimes
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
        lastGPU = [:]
        lastSampleNanos = nil
    }

    // MARK: - Helpers

    /// The entry with the largest `key`, ignoring those below `minimum`. Ties break by name for a stable choice.
    static func top<Value: Comparable>(
        _ entries: [ProcessUsage], by key: KeyPath<ProcessUsage, Value>, minimum: Value
    ) -> ProcessUsage? {
        entries.filter { $0[keyPath: key] >= minimum }.min {
            $0[keyPath: key] != $1[keyPath: key] ? $0[keyPath: key] > $1[keyPath: key] : $0.name < $1.name
        }
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
            return Group(id: bundle, name: name, path: bundle)
        }
        let name = (path as NSString).lastPathComponent
        return Group(id: path, name: name.isEmpty ? path : name, path: path)
    }
}
