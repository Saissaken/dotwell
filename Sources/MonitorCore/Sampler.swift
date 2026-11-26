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
    /// Average CPU die temperature in °C, when the Mac exposes its sensors.
    public var cpuTemperature: Float?
    public var ping: [PingTargetState] = []
    public var levels: [MetricKind: HealthLevel] = [:]
    /// The thresholds the levels were computed with, so the UI can color secondary values the same way.
    public var thresholds = Thresholds()
    /// Only filled while the popover is open (`detailed == true`).
    public var history: [String: [Float]] = [:]
    /// The app using the most of each resource, only sampled while the popover is open.
    public var topApps: TopApps?
    /// Route to the primary ping target, traced only while the popover is open.
    public var path: PathTrace?

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

    private var configuration: SamplerConfiguration
    private var step: Int { configuration.interval.seconds }

    private let cpuProbe = CPUProbe()
    private let memoryProbe = MemoryProbe()
    private let networkProbe = NetworkProbe()
    private let diskProbe = DiskProbe()
    private let powerProbe = PowerProbe()
    private let temperatureProbe = TemperatureProbe()
    private let processProbe = ProcessProbe()
    private let ping: PingEngine
    private lazy var traceroute = Traceroute(queue: queue)

    private var timer: DispatchSourceTimer?
    private var tick: UInt64 = 0
    private var lastNet: (NetworkCounters, UInt64)?
    private var lastDiskIO: (DiskIOCounters, UInt64)?
    private var current = Snapshot()

    private var series: [String: TieredSeries] = [:]
    private var pingSeries: [TieredSeries]
    private var primaryIndex: Int
    private var pendingPing: [Int: Float] = [:]

    private var debouncers: [MetricKind: LevelDebouncer] = [:]

    /// How long, in seconds, a level must hold before the icon follows it: (warning, critical, back down).
    private static let holdSeconds: [MetricKind: (Int, Int, Int)] = [
        .ping: (3, 3, 5),
        .cpu: (30, 60, 10),
        .memory: (5, 5, 10),
        .disk: (1, 1, 1),
        .power: (30, 30, 10),
        .thermal: (1, 1, 5),
    ]

    private var detailedFlag = false
    private var historyRange: HistoryRange = .seconds30

    public init(configuration: SamplerConfiguration = SamplerConfiguration()) {
        self.configuration = configuration
        let targets = configuration.activeTargets
        ping = PingEngine(targets: targets, queue: queue)
        pingSeries = Array(repeating: TieredSeries(), count: targets.count)
        primaryIndex = configuration.activePrimaryIndex
        current.thresholds = configuration.thresholds
        debouncers = Self.makeDebouncers(step: configuration.interval.seconds)
        ping.onResult = { [weak self] index, ms in self?.pendingPing[index] = ms ?? PingStats.lost }
    }

    public convenience init(targets: [PingTarget], primaryIndex: Int = 0) {
        self.init(configuration: SamplerConfiguration(targets: targets, primaryIndex: primaryIndex))
    }

    private static func makeDebouncers(step: Int) -> [MetricKind: LevelDebouncer] {
        func ticks(_ seconds: Int) -> Int { (seconds + step - 1) / step }
        return holdSeconds.mapValues { hold in
            LevelDebouncer(raiseWarning: ticks(hold.0), raiseCritical: ticks(hold.1), lowerAfter: ticks(hold.2))
        }
    }

    // MARK: - Control (call from any thread)

    public func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            _ = cpuProbe.sample()  // prime deltas
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.setEventHandler { [weak self] in self?.tickOnce() }
            timer = t
            schedule()
            t.resume()
        }
    }

    /// A quarter of the interval as leeway lets macOS coalesce wakeups with other work.
    private func schedule() {
        let interval = DispatchTimeInterval.seconds(step)
        timer?.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(step * 250))
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            ping.reset()
            traceroute.stop()
            current.path = nil
            pendingPing.removeAll()
            lastNet = nil
            lastDiskIO = nil
        }
    }

    /// Applies new settings from the next tick on. History is kept; ping history follows its target
    /// when targets are reordered, and starts empty for new ones.
    public func apply(_ newConfiguration: SamplerConfiguration) {
        queue.async { [self] in
            let old = configuration
            guard newConfiguration != old else { return }
            configuration = newConfiguration
            if newConfiguration.interval != old.interval {
                debouncers = Self.makeDebouncers(step: step)
                schedule()
            }
            let targets = newConfiguration.activeTargets
            if targets != old.activeTargets {
                var previous: [PingTarget: TieredSeries] = [:]
                for (target, series) in zip(old.activeTargets, pingSeries) where previous[target] == nil {
                    previous[target] = series
                }
                ping.reset()
                ping.targets = targets
                pendingPing.removeAll()
                pingSeries = targets.map { previous[$0] ?? TieredSeries() }
            }
            let oldPrimary = primaryIndex
            primaryIndex = newConfiguration.activePrimaryIndex
            if detailedFlag, targets != old.activeTargets || primaryIndex != oldPrimary {
                traceroute.stop()  // trace the new primary target instead
                current.path = nil
                startTrace()
            }
            current.thresholds = newConfiguration.thresholds
            if !newConfiguration.sampleTopApps {
                processProbe.reset()
                current.topApps = nil
            } else if !old.sampleTopApps, detailedFlag {
                current.topApps = processProbe.sample()
            }
            for kind in MetricKind.allCases where !newConfiguration.alerts.contains(kind) {
                current.levels[kind] = nil
                debouncers[kind]?.reset()
            }
            evaluate()
            publish()
        }
    }

    /// While detailed, snapshots carry history for `range`.
    public func setDetailed(_ detailed: Bool, range: HistoryRange) {
        queue.async { [self] in
            let opening = detailed && !detailedFlag
            detailedFlag = detailed
            historyRange = range
            if opening, configuration.sampleTopApps {
                current.topApps = processProbe.sample()  // memory right away, rates from the next sample
                startTrace()
            } else if !detailed {
                processProbe.reset()
                current.topApps = nil
                traceroute.stop()
                current.path = nil
            }
            if detailed { publish() }  // immediate data when the popover opens
        }
    }

    // MARK: - Tick

    /// True on the first tick and then once every `seconds` (or every tick, if the interval is longer).
    private func every(_ seconds: Int) -> Bool {
        (tick &- 1) % UInt64(max(1, seconds / step)) == 0
    }

    private func tickOnce() {
        tick &+= 1
        let now = DispatchTime.now().uptimeNanoseconds

        // Ping: record replies collected since the last tick, then send the next round.
        // ICMP every second; TCP targets every 5 s to stay polite.
        for (i, value) in pendingPing { pingSeries[i].append(value) }
        pendingPing.removeAll(keepingCapacity: true)
        let due = ping.targets.indices.filter { i in
            if ping.targets[i].method != .icmp { return every(5) }
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
        if every(30) || current.disk == nil { current.disk = diskProbe.space() }
        if powerProbe.hasBattery, every(2) || current.power == nil {
            current.power = powerProbe.sample()
        }
        if let w = current.power?.watts { append(SeriesKey.power, Float(w)) }
        current.thermal = ProcessInfo.processInfo.thermalState
        if every(5) { current.cpuTemperature = temperatureProbe.sample() }
        // Per-process usage costs one syscall per process, so it only runs with the popover open:
        // first rates one second after opening, then every 2 s like Activity Monitor's fast setting.
        if detailedFlag, configuration.sampleTopApps, let elapsed = processProbe.elapsed(now: now),
            elapsed >= (current.topApps?.hasRates == true ? 1_900_000_000 : 900_000_000)
        {
            current.topApps = processProbe.sample(now: now)
        }

        if detailedFlag && traceroute.isRunning {
            current.path = traceroute.snapshot()
            traceroute.probeRound()
        }

        evaluate()
        publish()
    }

    /// Traces the route to the primary target while the popover is open. Not for the router itself
    /// (the route is one hop) or TCP targets, which drop the ICMP probes.
    private func startTrace() {
        guard ping.targets.indices.contains(primaryIndex) else { return }
        let target = ping.targets[primaryIndex]
        guard !target.isGateway, target.method == .icmp else { return }
        traceroute.start(host: target.host)
        traceroute.probeRound()
        current.path = traceroute.snapshot()  // the path shows "tracing" right away instead of popping in
    }

    private func append(_ key: String, _ value: Float) {
        series[key, default: TieredSeries()].append(value)
    }

    private func evaluate() {
        let thresholds = configuration.thresholds
        var raw: [MetricKind: HealthLevel] = [:]
        current.ping = ping.targets.indices.map { i in
            PingTargetState(
                index: i, target: ping.targets[i],
                stats: PingStats.compute(pingSeries[i].recent(pingWindow)),
                isPrimary: i == primaryIndex)
        }
        if let primary = current.primaryPing, !pingSeries[primary.index].recent(1).isEmpty {
            raw[.ping] = thresholds.ping(primary.stats)
        } else if current.ping.isEmpty {
            current.levels[.ping] = nil
        }
        if let cpu = current.cpu { raw[.cpu] = thresholds.cpu(cpu) }
        if let mem = current.memory { raw[.memory] = thresholds.memory(mem.pressure) }
        if let disk = current.disk { raw[.disk] = thresholds.disk(disk) }
        if let power = current.power { raw[.power] = thresholds.power(power) }
        raw[.thermal] = thresholds.thermal(current.thermal)

        for (kind, level) in raw where configuration.alerts.contains(kind) {
            current.levels[kind] = debouncers[kind]?.feed(level) ?? level
        }
    }

    /// Ping stats cover the last 10 s, but at least 5 samples so one lost reply isn't 100 % loss.
    private var pingWindow: Int { max(5, 10 / step) }

    private func publish() {
        var snap = current
        if detailedFlag {
            var h: [String: [Float]] = [:]
            for (k, s) in series { h[k] = s.values(for: historyRange, interval: step) }
            for i in pingSeries.indices {
                h[SeriesKey.ping(i)] = pingSeries[i].values(for: historyRange, interval: step)
            }
            snap.history = h
        }
        guard let onSnapshot else { return }
        DispatchQueue.main.async { onSnapshot(snap) }
    }
}
