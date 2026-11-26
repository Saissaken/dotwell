import Foundation

/// Live state of one ping target.
public struct PingTargetState: Sendable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var target: PingTarget
    public var stats: PingStats
    public var isPrimary: Bool

    public init(index: Int, target: PingTarget, stats: PingStats, isPrimary: Bool) {
        self.index = index
        self.target = target
        self.stats = stats
        self.isPrimary = isPrimary
    }
}

/// Immutable picture of the system handed to the UI once per tick.
public struct Snapshot: Sendable {
    public var cpu: Float?
    public var memory: MemorySample?
    public var disk: DiskSpace?
    public var diskReadBytesPerSec: Double = 0
    public var diskWriteBytesPerSec: Double = 0
    public var power: PowerSample?
    public var networkDownBitsPerSec: Double = 0
    public var networkUpBitsPerSec: Double = 0
    public var thermal: ProcessInfo.ThermalState = .nominal
    public var ping: [PingTargetState] = []
    public var levels: [MetricKind: HealthLevel] = [:]
    /// Only filled while the popover is open (`detailed == true`).
    public var history: [String: [Float]] = [:]
    /// Heaviest apps, only sampled while the popover is open.
    public var processes: TopProcesses?

    public init() {}

    public var overall: HealthLevel { levels.values.max() ?? .ok }
    public func level(_ kind: MetricKind) -> HealthLevel { levels[kind] ?? .ok }

    public var primaryPing: PingTargetState? { ping.first(where: \.isPrimary) }
}

/// History keys used in `Snapshot.history`.
public enum SeriesKey {
    public static let cpu = "cpu"
    public static let memory = "memory"
    public static let power = "power"
    public static let netDown = "net.down"
    public static let netUp = "net.up"
    public static let diskRead = "disk.read"
    public static let diskWrite = "disk.write"
    public static func ping(_ index: Int) -> String { "ping.\(index)" }
}

/// Drives all probes from a single timer on one serial utility queue.
/// All mutable state is confined to `queue`, hence `@unchecked Sendable`.
public final class Sampler: @unchecked Sendable {
    public let queue = DispatchQueue(label: "monitor.sampler", qos: .utility)
    /// Called on the main queue after each tick.
    public var onSnapshot: ((Snapshot) -> Void)?

    public var thresholds = Thresholds()
    private let interval: TimeInterval = 1

    private let cpuProbe = CPUProbe()
    private let memoryProbe = MemoryProbe()
    private let networkProbe = NetworkProbe()
    private let diskProbe = DiskProbe()
    private let powerProbe = PowerProbe()
    private let processProbe = ProcessProbe()
    private let ping: PingEngine

    private var timer: DispatchSourceTimer?
    private var tick: UInt64 = 0
    private var lastNet: (NetworkCounters, UInt64)?
    private var lastDiskIO: (DiskIOCounters, UInt64)?
    private var current = Snapshot()

    private var series: [String: TieredSeries] = [:]
    private var pingSeries: [TieredSeries]
    private var primaryIndex: Int
    private var pendingPing: [Int: Float] = [:]

    private var debouncers: [MetricKind: LevelDebouncer] = [
        .ping: LevelDebouncer(raiseWarning: 3, raiseCritical: 3, lowerAfter: 5),
        .cpu: LevelDebouncer(raiseWarning: 30, raiseCritical: 60, lowerAfter: 10),
        .memory: LevelDebouncer(raiseWarning: 5, raiseCritical: 5, lowerAfter: 10),
        .disk: LevelDebouncer(raiseWarning: 1, raiseCritical: 1, lowerAfter: 1),
        .power: LevelDebouncer(raiseWarning: 30, raiseCritical: 30, lowerAfter: 10),
        .thermal: LevelDebouncer(raiseWarning: 1, raiseCritical: 1, lowerAfter: 5),
    ]

    private var detailedFlag = false
    private var historyRange: HistoryRange = .seconds30

    public init(targets: [PingTarget] = PingTarget.defaults, primaryIndex: Int = PingTarget.defaultPrimaryIndex) {
        ping = PingEngine(targets: targets, queue: queue)
        pingSeries = Array(repeating: TieredSeries(), count: targets.count)
        self.primaryIndex = min(max(0, primaryIndex), max(0, targets.count - 1))
        ping.onResult = { [weak self] index, ms in self?.pendingPing[index] = ms ?? PingStats.lost }
    }

    // MARK: - Control (call from any thread)

    public func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            _ = cpuProbe.sample()  // prime deltas
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
            t.setEventHandler { [weak self] in self?.step() }
            t.resume()
            timer = t
        }
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            ping.reset()
            pendingPing.removeAll()
            lastNet = nil
            lastDiskIO = nil
        }
    }

    /// While detailed, snapshots carry history for `range`.
    public func setDetailed(_ detailed: Bool, range: HistoryRange) {
        queue.async { [self] in
            let opening = detailed && !detailedFlag
            detailedFlag = detailed
            historyRange = range
            if opening {
                current.processes = processProbe.sample()  // memory ranking right away, CPU from the next one
            } else if !detailed {
                processProbe.reset()
                current.processes = nil
            }
            if detailed { publish() }  // immediate data when the popover opens
        }
    }

    // MARK: - Tick

    private func step() {
        tick &+= 1
        let now = DispatchTime.now().uptimeNanoseconds

        // Ping: record replies collected since the last tick, then send the next round.
        // ICMP every second; TCP targets every 5 s to stay polite.
        for (i, value) in pendingPing { pingSeries[i].append(value) }
        pendingPing.removeAll(keepingCapacity: true)
        let due = ping.targets.indices.filter { i in
            if case .tcp = ping.targets[i].method { return tick % 5 == 1 }
            return true
        }
        ping.probe(due)

        if let cpu = cpuProbe.sample() {
            current.cpu = cpu
            append(SeriesKey.cpu, cpu)
        }
        if let mem = memoryProbe.sample() {
            current.memory = mem
            append(SeriesKey.memory, mem.usedFraction)
        }
        if let net = networkProbe.sample() {
            if let (prev, t) = lastNet {
                let r = NetworkCounters.rates(from: prev, to: net, seconds: Double(now - t) / 1e9)
                current.networkDownBitsPerSec = r.down
                current.networkUpBitsPerSec = r.up
                append(SeriesKey.netDown, Float(r.down))
                append(SeriesKey.netUp, Float(r.up))
            }
            lastNet = (net, now)
        }
        if let io = diskProbe.ioCounters() {
            if let (prev, t) = lastDiskIO {
                let s = Double(now - t) / 1e9
                let rd = io.bytesRead >= prev.bytesRead ? Double(io.bytesRead - prev.bytesRead) / s : 0
                let wr = io.bytesWritten >= prev.bytesWritten ? Double(io.bytesWritten - prev.bytesWritten) / s : 0
                current.diskReadBytesPerSec = rd
                current.diskWriteBytesPerSec = wr
                append(SeriesKey.diskRead, Float(rd))
                append(SeriesKey.diskWrite, Float(wr))
            }
            lastDiskIO = (io, now)
        }
        // Slow-changing values.
        if tick % 30 == 1 || current.disk == nil { current.disk = diskProbe.space() }
        if powerProbe.hasBattery, tick % 2 == 1 || current.power == nil {
            current.power = powerProbe.sample()
        }
        if let w = current.power?.watts { append(SeriesKey.power, Float(w)) }
        current.thermal = ProcessInfo.processInfo.thermalState
        // Per-process usage costs one syscall per process, so it only runs with the popover open:
        // first CPU ranking one second after opening, then every 2 s like Activity Monitor's fast setting.
        if detailedFlag, let elapsed = processProbe.elapsed(now: now),
            elapsed >= (current.processes?.byCPU.isEmpty == false ? 1_900_000_000 : 900_000_000)
        {
            current.processes = processProbe.sample(now: now)
        }

        evaluate()
        publish()
    }

    private func append(_ key: String, _ value: Float) {
        series[key, default: TieredSeries()].append(value)
    }

    private func evaluate() {
        var raw: [MetricKind: HealthLevel] = [:]
        current.ping = ping.targets.indices.map { i in
            PingTargetState(
                index: i, target: ping.targets[i],
                stats: PingStats.compute(pingSeries[i].recent(10)),
                isPrimary: i == primaryIndex)
        }
        if let primary = current.primaryPing, !pingSeries[primary.index].recent(1).isEmpty {
            raw[.ping] = thresholds.ping(primary.stats)
        }
        if let cpu = current.cpu { raw[.cpu] = thresholds.cpu(cpu) }
        if let mem = current.memory { raw[.memory] = thresholds.memory(mem.pressure) }
        if let disk = current.disk { raw[.disk] = thresholds.disk(disk) }
        if let power = current.power { raw[.power] = thresholds.power(power) }
        raw[.thermal] = thresholds.thermal(current.thermal)

        for (kind, level) in raw {
            current.levels[kind] = debouncers[kind]?.feed(level) ?? level
        }
    }

    private func publish() {
        var snap = current
        if detailedFlag {
            var h: [String: [Float]] = [:]
            for (k, s) in series { h[k] = s.values(for: historyRange) }
            for i in pingSeries.indices { h[SeriesKey.ping(i)] = pingSeries[i].values(for: historyRange) }
            snap.history = h
        }
        guard let onSnapshot else { return }
        DispatchQueue.main.async { onSnapshot(snap) }
    }
}
