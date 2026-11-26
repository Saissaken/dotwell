import Foundation

/// Live state of one ping target.
public struct PingTargetState: Sendable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var target: PingTarget
    public var stats: PingStats
    public var isPrimary: Bool
    /// The IPv4 address being probed, once known.
    public var address: String?
    /// Every reading of the last minute, oldest first, each reply once and lost ones as `PingStats.lost`.
    /// Only filled while the popover is open, for the row's detail.
    public var lastMinute: [Float] = []
    /// The last minute on the history's half-second clock (120 points), so a chart of it keeps time even
    /// when readings came at different intervals. Only filled while the popover is open.
    public var lastMinuteChart: [Float] = []
    /// How many seconds `lastMinute` covers: 60 once the row has a minute of readings.
    public var lastMinuteSeconds = 60
    /// Milliseconds between two readings of this target at the current interval.
    public var probeIntervalMilliseconds: Int

    public init(
        index: Int, target: PingTarget, stats: PingStats, isPrimary: Bool, address: String? = nil,
        probeIntervalMilliseconds: Int = 1000
    ) {
        self.index = index
        self.target = target
        self.stats = stats
        self.isPrimary = isPrimary
        self.address = address
        self.probeIntervalMilliseconds = probeIntervalMilliseconds
    }

    /// Average, minimum, maximum, loss and jitter over `lastMinute`.
    public var minuteStats: PingStats { PingStats.compute(lastMinute) }
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
    /// Average fan speed in RPM (0 while stopped); nil on Macs without fans.
    public var fanRPM: Double?
    /// Nil on Macs whose GPU can't be read. Its readings are only taken while the popover is open.
    public var gpu: GPUSample?
    public var ping: [PingTargetState] = []
    public var levels: [MetricKind: HealthLevel] = [:]
    /// The thresholds the levels were computed with, so the UI can color secondary values the same way.
    public var thresholds = Thresholds()
    /// Only filled while the popover is open (`detailed == true`).
    public var history: [String: [Float]] = [:]
    /// The app using the most of each resource, only sampled while the popover is open.
    public var topApps: TopApps?
    /// Route to the primary ping target, or to the one picked with `Sampler.traceRoute(to:)`, traced only
    /// while the popover is open.
    public var path: PathTrace?
    /// Index in `ping` of the target `path` leads to.
    public var pathIndex: Int?
    /// How far the charts have scrolled toward their next point, so they can slide instead of jumping.
    /// Only filled while the popover is open.
    public var chartMotion: ChartMotion?
    /// Points a full chart of the range on screen holds (see `TieredSeries.points(for:stepSlots:)`), so charts
    /// keep the same time scale while their history is still filling. Only filled while the popover is open.
    public var chartPoints: Int?

    public init() {}

    public var overall: HealthLevel { levels.values.max() ?? .ok }
    public func level(_ kind: MetricKind) -> HealthLevel { levels[kind] ?? .ok }

    public var primaryPing: PingTargetState? { ping.first(where: \.isPrimary) }
}

/// Lets the popover's charts scroll smoothly: each new point slides in from the right over the time it takes
/// to get the next one, instead of the whole line jumping one step when it arrives.
public struct ChartMotion: Sendable, Equatable {
    /// When the tick that produced the history ran.
    public var takenAt: Date
    /// Fraction (0..<1) of the time between two chart points that had already passed at `takenAt`. It is not
    /// zero on the 5 min and 1 h ranges, where one point averages 5 or 30 samples.
    public var phase: Double
    /// Seconds between two chart points.
    public var period: Double

    public init(takenAt: Date, phase: Double, period: Double) {
        self.takenAt = takenAt
        self.phase = phase
        self.period = period
    }

    /// How far the newest point has slid in at `date`, from 0 (just arrived, one step past the right edge)
    /// to 1 (at rest at the right edge).
    public func progress(at date: Date) -> Double {
        guard period > 0 else { return 1 }
        return min(1, max(0, phase + date.timeIntervalSince(takenAt) / period))
    }
}

/// History keys used in `Snapshot.history`.
public enum SeriesKey {
    public static let cpu = "cpu"
    /// Only recorded while the popover is open, and cleared when it closes.
    public static let gpu = "gpu"
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
    /// The reading interval in force: the popover's while it is open, the slower one while it is closed.
    private var interval: SamplingInterval {
        detailedFlag ? configuration.openInterval : configuration.closedInterval
    }

    private let cpuProbe = CPUProbe()
    private let memoryProbe = MemoryProbe()
    private let networkProbe = NetworkProbe()
    private let diskProbe = DiskProbe()
    private let powerProbe = PowerProbe()
    private let temperatureProbe = TemperatureProbe()
    private let processProbe = ProcessProbe()
    private let gpuProbe = GPUProbe()
    private let ping: PingEngine
    private lazy var traceroute = Traceroute(queue: queue)

    private var timer: DispatchSourceTimer?
    private var tick: UInt64 = 0
    /// Half-second history slots covered so far (see `TieredSeries`). Drives the time-based schedules, so
    /// "every 5 s" means 5 seconds whatever the reading interval.
    private var slots: UInt64 = 0
    private var slotsBeforeTick: UInt64 = 0
    /// The slot count when each ping row last recorded a reply, so a reply fills the time since the last one.
    private var pingSlots: [UInt64]
    private var lastTickDate: Date?
    private var lastNet: (NetworkCounters, UInt64)?
    private var lastDiskIO: (DiskIOCounters, UInt64)?
    private var current = Snapshot()

    private var series: [String: TieredSeries] = [:]
    private var pingSeries: [TieredSeries]
    /// Each ping row's own readings, for the last minute in its detail.
    private var pingLogs: [PingReadingLog]
    private var primaryIndex: Int
    /// The target picked from a ping row's menu to trace instead of the primary one, until the popover closes.
    private var traceOverride: Int?
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
    /// The overall level last handed to the main queue. While the popover is closed, snapshots only go there
    /// when it changes, since the menu bar dot is all that shows them.
    private var publishedLevel: HealthLevel?
    private var historyRange: HistoryRange = .seconds30

    public init(configuration: SamplerConfiguration = SamplerConfiguration()) {
        self.configuration = configuration
        let targets = configuration.activeTargets
        ping = PingEngine(targets: targets, queue: queue)
        pingSeries = Array(repeating: TieredSeries(), count: targets.count)
        pingLogs = Array(repeating: PingReadingLog(), count: targets.count)
        pingSlots = Array(repeating: 0, count: targets.count)
        primaryIndex = configuration.activePrimaryIndex
        current.thresholds = configuration.thresholds
        debouncers = Self.makeDebouncers()
        ping.onResult = { [weak self] index, ms in self?.pendingPing[index] = ms ?? PingStats.lost }
    }

    public convenience init(targets: [PingTarget], primaryIndex: Int = 0) {
        self.init(configuration: SamplerConfiguration(targets: targets, primaryIndex: primaryIndex))
    }

    /// Holds are counted in half-second slots, and each reading feeds the slots it covers.
    private static func makeDebouncers() -> [MetricKind: LevelDebouncer] {
        func slots(_ seconds: Int) -> Int { seconds * 1000 / TieredSeries.slotMilliseconds }
        return holdSeconds.mapValues { hold in
            LevelDebouncer(raiseWarning: slots(hold.0), raiseCritical: slots(hold.1), lowerAfter: slots(hold.2))
        }
    }

    // MARK: - Control (call from any thread)

    public func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            _ = cpuProbe.sample()  // prime deltas
            current.cpuTemperature = temperatureProbe.sample()  // finds the sensors once, off the popover's path
            current.fanRPM = temperatureProbe.fanRPM()
            if gpuProbe.isAvailable { current.gpu = GPUSample(coreCount: gpuProbe.coreCount) }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.setEventHandler { [weak self] in self?.tickOnce() }
            timer = t
            // The first reading comes a second after the CPU deltas are primed, not a whole closed interval later.
            schedule(firstAfter: min(interval.milliseconds, 1000))
            t.resume()
        }
    }

    /// A quarter of the interval as leeway lets macOS coalesce wakeups with other work.
    private func schedule(firstAfter first: Int? = nil) {
        let ms = interval.milliseconds
        timer?.schedule(
            deadline: .now() + .milliseconds(first ?? ms), repeating: .milliseconds(ms), leeway: .milliseconds(ms / 4))
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            ping.reset()
            stopTrace()
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
            if newConfiguration.openInterval != old.openInterval
                || newConfiguration.closedInterval != old.closedInterval
            {
                schedule()
            }
            let targets = newConfiguration.activeTargets
            if targets != old.activeTargets {
                var previous: [PingTarget: TieredSeries] = [:]
                var previousLogs: [PingTarget: PingReadingLog] = [:]
                for (target, log) in zip(old.activeTargets, pingLogs) where previousLogs[target] == nil {
                    previousLogs[target] = log
                }
                for (target, series) in zip(old.activeTargets, pingSeries) where previous[target] == nil {
                    previous[target] = series
                }
                ping.reset()
                ping.targets = targets
                pendingPing.removeAll()
                pingSeries = targets.map { previous[$0] ?? TieredSeries() }
                pingLogs = targets.map { previousLogs[$0] ?? PingReadingLog() }
                pingSlots = Array(repeating: slots, count: targets.count)
            }
            let oldPrimary = primaryIndex
            primaryIndex = newConfiguration.activePrimaryIndex
            if targets != old.activeTargets || primaryIndex != oldPrimary { traceOverride = nil }
            if detailedFlag, targets != old.activeTargets || primaryIndex != oldPrimary {
                stopTrace()  // trace the new primary target instead
                startTrace()
            }
            current.thresholds = newConfiguration.thresholds
            if !newConfiguration.readsTemperature { current.cpuTemperature = nil }
            if !newConfiguration.sampleTopApps {
                processProbe.reset()
                current.topApps = nil
            } else if !old.sampleTopApps, detailedFlag {
                current.topApps = processProbe.sample(gpuTimes: gpuTimes())
            }
            if newConfiguration.sampleGPU != old.sampleGPU {
                stopGPU()
                if detailedFlag { startGPU() }
            }
            for kind in MetricKind.allCases where !newConfiguration.alerts.contains(kind) {
                current.levels[kind] = nil
                debouncers[kind]?.reset()
            }
            evaluate()
            publish(always: true)
        }
    }

    /// While detailed, snapshots carry history for `range`.
    public func setDetailed(_ detailed: Bool, range: HistoryRange) {
        queue.async { [self] in
            let opening = detailed && !detailedFlag
            let wasInterval = interval
            detailedFlag = detailed
            if interval != wasInterval { schedule() }
            historyRange = range
            if opening {
                if configuration.readsTemperature {
                    current.cpuTemperature = temperatureProbe.sample()
                    current.fanRPM = temperatureProbe.fanRPM()
                }
                startGPU()
                if configuration.sampleTopApps {
                    // Memory right away, rates from the next sample.
                    current.topApps = processProbe.sample(gpuTimes: gpuTimes())
                }
                startTrace()
                current.ping = pingStates()  // the rows' last minute, before the first tick fills it
            } else if !detailed {
                processProbe.reset()
                current.topApps = nil
                stopGPU()
                traceOverride = nil
                stopTrace()
                current.ping = pingStates()  // drop the last minute of readings
            }
            if detailed { publish() }  // immediate data when the popover opens
        }
    }

    /// Traces the route to ping target `index` instead of the primary one, or back to the primary one with
    /// nil. Only while the popover is open; closing it goes back to the primary target.
    public func traceRoute(to index: Int?) {
        queue.async { [self] in
            guard detailedFlag else { return }
            let wanted = index == primaryIndex ? nil : index
            guard wanted != traceOverride else { return }
            if let wanted {
                let host = Self.traceHost(for: wanted, targets: ping.targets, picked: true, address: ping.probedAddress)
                guard host != nil else { return }  // e.g. the ISP router isn't found yet
            }
            traceOverride = wanted
            stopTrace()
            startTrace()
            publish(always: true)
        }
    }

    // MARK: - Tick

    /// True on the first tick and then on the tick that crosses each multiple of `seconds` (every tick, if the
    /// interval is longer).
    private func every(_ seconds: Int) -> Bool {
        let period = UInt64(seconds * 1000 / TieredSeries.slotMilliseconds)
        return tick == 1 || slotsBeforeTick / period != slots / period
    }

    private func tickOnce() {
        tick &+= 1
        slotsBeforeTick = slots
        let covered = interval.slots
        slots &+= UInt64(covered)
        lastTickDate = Date()
        let now = DispatchTime.now().uptimeNanoseconds

        // Ping: record the replies to the last round. The next round goes out at the end of the tick.
        ping.collect()
        for (i, value) in pendingPing where pingSeries.indices.contains(i) {
            pingSeries[i].append(value, slots: Int(min(slots &- pingSlots[i], 300)))
            pingLogs[i].append(value, slot: slots)
            pingSlots[i] = slots
        }
        pendingPing.removeAll(keepingCapacity: true)

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
        // Temperature and fans are only shown in the popover.
        if detailedFlag, configuration.readsTemperature, every(5) {
            current.cpuTemperature = temperatureProbe.sample()
            current.fanRPM = temperatureProbe.fanRPM()
        }
        if detailedFlag { sampleGPU(now: now) }
        // Per-process usage costs one syscall per process, so it only runs with the popover open:
        // first rates one second after opening, then every 2 s like Activity Monitor's fast setting.
        if detailedFlag, configuration.sampleTopApps, let elapsed = processProbe.elapsed(now: now),
            elapsed >= (current.topApps?.hasRates == true ? 1_900_000_000 : 900_000_000)
        {
            current.topApps = processProbe.sample(now: now, gpuTimes: gpuTimes())
        }

        if detailedFlag && traceroute.isRunning && every(1) {
            current.path = traceroute.snapshot()
            traceroute.probeRound()
        }

        evaluate(covered: covered)
        publish()

        // Sent last, so TCP handshakes complete while the queue is idle instead of waiting behind this tick.
        // ICMP every tick; TCP and HTTPS targets every 5 s to stay polite.
        ping.probe(ping.targets.indices.filter { ping.targets[$0].method == .icmp || every(5) })
    }

    // MARK: - GPU

    private var readsGPU: Bool { configuration.sampleGPU && gpuProbe.isAvailable }

    /// Per-app GPU time for the top apps, when the GPU card is on.
    private func gpuTimes() -> [pid_t: UInt64]? {
        readsGPU ? gpuProbe.processGPUTimes() : nil
    }

    /// First readings when the popover opens. Power needs a second sample, so it shows from the next tick.
    private func startGPU() {
        guard readsGPU else { return }
        current.gpu?.utilization = gpuProbe.utilization()
        current.gpu?.temperature = gpuProbe.temperature()
        _ = gpuProbe.watts()
    }

    private func sampleGPU(now: UInt64) {
        guard readsGPU else { return }
        let utilization = gpuProbe.utilization()
        current.gpu?.utilization = utilization
        if let utilization { append(SeriesKey.gpu, utilization) }
        current.gpu?.watts = gpuProbe.watts(now: now)
        if every(5) { current.gpu?.temperature = gpuProbe.temperature() }
    }

    /// Nothing about the GPU is read while the popover is closed, so its readings and history are dropped
    /// instead of showing stale values or a chart with a gap.
    private func stopGPU() {
        gpuProbe.reset()
        series[SeriesKey.gpu] = nil
        if current.gpu != nil { current.gpu = GPUSample(coreCount: gpuProbe.coreCount) }
    }

    /// Traces the route to the primary target, or the one picked from its row, while the popover is open.
    /// The primary target is not traced when it is the router, ISP or DNS row: their address is found on the
    /// current network and the route to them is a hop or two. Picked from its row, any target but the router
    /// is traced, to the address it is measured at. Cloud hosts that drop ICMP still show every router on the
    /// way; their own round trip comes from the row's measurement (see `NetworkPath`).
    private func startTrace() {
        let index = traceOverride ?? primaryIndex
        let host = Self.traceHost(
            for: index, targets: ping.targets, picked: traceOverride != nil, address: ping.probedAddress)
        guard let host else { return }
        traceroute.start(host: host)
        traceroute.probeRound()
        current.path = traceroute.snapshot()  // the path shows "tracing" right away instead of popping in
        current.pathIndex = index
    }

    private func stopTrace() {
        traceroute.stop()
        current.path = nil
        current.pathIndex = nil
    }

    /// What to trace for target `index`: its host name, or for a target found on this network, the address
    /// it is measured at. Nil when it shouldn't (or can't yet) be traced.
    static func traceHost(
        for index: Int, targets: [PingTarget], picked: Bool, address: (Int) -> String?
    ) -> String? {
        guard targets.indices.contains(index) else { return nil }
        let target = targets[index]
        if target.isGateway { return nil }
        if target.isDiscovered { return picked ? address(index) : nil }
        return target.host
    }

    /// Milliseconds between two readings of a target: ICMP every tick, the others every 5 s, or every tick when
    /// ticks are further apart (see `tickOnce`).
    static func probeInterval(_ method: PingTarget.Method, interval: SamplingInterval) -> Int {
        method == .icmp ? interval.milliseconds : max(5000, interval.milliseconds)
    }

    private func append(_ key: String, _ value: Float) {
        series[key, default: TieredSeries()].append(value, slots: interval.slots)
    }

    /// `covered`: the half-second slots the latest reading stands for, so alert holds are counted in time.
    private func evaluate(covered: Int = 1) {
        let thresholds = configuration.thresholds
        var raw: [MetricKind: HealthLevel] = [:]
        current.ping = pingStates()
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
            current.levels[kind] = debouncers[kind]?.feed(level, weight: covered) ?? level
        }
    }

    /// The ping rows. The last minute is only copied while the popover is open.
    private func pingStates() -> [PingTargetState] {
        ping.targets.indices.map { i in
            let method = ping.targets[i].method
            var state = PingTargetState(
                index: i, target: ping.targets[i],
                stats: PingStats.compute(pingSeries[i].recent(pingWindow)),
                isPrimary: i == primaryIndex, address: ping.probedAddress(i),
                probeIntervalMilliseconds: Self.probeInterval(method, interval: interval))
            if detailedFlag {
                let minuteSlots = UInt64(60_000 / TieredSeries.slotMilliseconds)
                let minute = pingLogs[i].readings(after: slots > minuteSlots ? slots - minuteSlots : 0)
                state.lastMinute = minute.values
                state.lastMinuteChart = pingSeries[i].recent(Int(minuteSlots))
                if let first = minute.firstSlot {
                    let span = Int(slots - first) * TieredSeries.slotMilliseconds + state.probeIntervalMilliseconds
                    state.lastMinuteSeconds = min(60, span / 1000)
                }
            }
            return state
        }
    }

    /// Ping stats cover the last 10 s, but at least 5 readings so one lost reply isn't 100 % loss.
    private var pingWindow: Int { min(300, max(20, 5 * interval.slots)) }

    /// The latest values, without history. Call from the main queue when the popover opens, so its first
    /// frame is current even though closed-popover snapshots are not sent there every tick.
    public func latest() -> Snapshot {
        queue.sync { current }
    }

    /// Slots per chart point for the range on screen, as `TieredSeries` buckets them. Every series starts on
    /// the first tick, so they all share the phase of `tick`.
    private func chartMotion() -> ChartMotion? {
        guard let lastTickDate else { return nil }
        let slotsPerPoint: UInt64
        switch historyRange {
        case .seconds30: slotsPerPoint = UInt64(interval.slots)
        case .minutes5: slotsPerPoint = UInt64(TieredSeries.midSlots)
        case .hour1: slotsPerPoint = UInt64(TieredSeries.longSlots)
        }
        let slotSeconds = Double(TieredSeries.slotMilliseconds) / 1000
        return ChartMotion(
            takenAt: lastTickDate, phase: Double(slots % slotsPerPoint) / Double(slotsPerPoint),
            period: Double(slotsPerPoint) * slotSeconds)
    }

    private func publish(always: Bool = false) {
        if !detailedFlag, !always, current.overall == publishedLevel { return }
        publishedLevel = current.overall
        var snap = current
        if detailedFlag {
            var h: [String: [Float]] = [:]
            let stepSlots = interval.slots
            for (k, s) in series { h[k] = s.values(for: historyRange, stepSlots: stepSlots) }
            for i in pingSeries.indices {
                h[SeriesKey.ping(i)] = pingSeries[i].values(for: historyRange, stepSlots: stepSlots)
            }
            snap.history = h
            snap.chartMotion = chartMotion()
            snap.chartPoints = TieredSeries.points(for: historyRange, stepSlots: stepSlots)
        }
        guard let onSnapshot else { return }
        DispatchQueue.main.async { onSnapshot(snap) }
    }
}
