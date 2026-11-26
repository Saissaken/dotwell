import Darwin
import Dispatch

/// One router (or the destination) on the way to a host, as seen by `Traceroute`.
public struct TraceHop: Sendable, Equatable {
    /// Distance from this Mac: 1 is the first router.
    public var ttl: Int
    /// Dotted IPv4 address of the last router that answered at this distance, nil while none has.
    public var address: String?
    /// Reverse DNS name, when the address has one.
    public var hostname: String?
    /// Latency and loss over the most recent probes.
    public var stats: PingStats
    /// True for the destination itself.
    public var isDestination: Bool

    public init(ttl: Int, address: String?, hostname: String?, stats: PingStats, isDestination: Bool) {
        self.ttl = ttl
        self.address = address
        self.hostname = hostname
        self.stats = stats
        self.isDestination = isDestination
    }

    /// No router answered at this distance yet (many drop the probes on purpose).
    public var isSilent: Bool { address == nil }
}

/// The route to the primary ping target, as last measured.
public struct PathTrace: Sendable, Equatable {
    /// Hops in order from this Mac; silent hops are included so distances stay visible.
    public var hops: [TraceHop]
    /// Rounds of probes sent so far.
    public var rounds: Int

    public init(hops: [TraceHop], rounds: Int) {
        self.hops = hops
        self.rounds = rounds
    }

    public var reachedDestination: Bool { hops.last?.isDestination == true }
}

/// MTR-style continuous traceroute. Each round sends one ICMP echo per distance (TTL); routers answer with
/// "time exceeded" and the destination with an echo reply. Uses the same unprivileged datagram ICMP socket as
/// `PingEngine`, so it needs no root and spawns nothing. It only runs between `start` and `stop`
/// (while the popover is open); all state is confined to `queue`.
final class Traceroute {
    static let maxHops = 30
    /// Probes per hop that the stats cover.
    static let window = 10

    private let queue: DispatchQueue
    /// Random per trace and distinct from `PingEngine`'s, so each ignores the others' replies
    /// (every ICMP socket sees every ICMP packet).
    private let identifier: UInt16 = {
        let id = UInt16.random(in: 0...UInt16.max)
        return id == UInt16(truncatingIfNeeded: getpid()) ? id ^ 0x5a5a : id
    }()
    private var sequence: UInt16 = 0
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var pending: [UInt16: (ttl: Int, sentAt: UInt64)] = [:]
    private let timeoutNanos: UInt64 = 2_000_000_000

    private var host: String?
    private var destination: in_addr?
    private var resolving = false
    private var rounds = 0
    /// Index = TTL − 1.
    private var hops: [HopRecord] = []
    /// Smallest TTL at which the destination answered.
    private var destinationTTL: Int?

    /// Reverse DNS results, kept across runs (a few dozen strings at most).
    private var names: [UInt32: String] = [:]
    private var lookingUp: Set<UInt32> = []

    private struct HopRecord {
        var address: in_addr?
        var samples = RingBuffer(capacity: Traceroute.window)
    }

    /// Off for quick one-off traces whose router names nobody sees.
    private let resolvesNames: Bool

    init(queue: DispatchQueue, resolvesNames: Bool = true) {
        self.queue = queue
        self.resolvesNames = resolvesNames
    }

    deinit {
        readSource?.cancel()
    }

    var isRunning: Bool { host != nil }

    /// Starts tracing `host` (a literal IPv4 address or a name). Must be called on `queue`.
    func start(host: String) {
        dispatchPrecondition(condition: .onQueue(queue))
        stop()
        self.host = host
        var literal = in_addr()
        if inet_pton(AF_INET, host, &literal) == 1 {
            destination = literal
        } else {
            resolve(host)
        }
    }

    /// Stops tracing and releases the socket. Must be called on `queue`.
    func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        readSource?.cancel()
        readSource = nil
        socketFD = -1
        host = nil
        destination = nil
        pending.removeAll()
        hops.removeAll()
        destinationTTL = nil
        rounds = 0
    }

    /// Sends the next round of probes. Call about once a second, on `queue`.
    func probeRound() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard isRunning, let destination, ensureSocket() else { return }
        expire(now: Self.now())
        rounds += 1
        let limit = probeLimit()
        if hops.count < limit { hops.append(contentsOf: Array(repeating: HopRecord(), count: limit - hops.count)) }
        for ttl in 1...limit { send(ttl: ttl, to: destination) }
    }

    /// The trace so far, or nil before the first round.
    func snapshot() -> PathTrace? {
        dispatchPrecondition(condition: .onQueue(queue))
        guard isRunning, rounds > 0 else { return nil }
        // Leave out the silent tail past the last hop that answered, unless the destination did.
        let shown = destinationTTL ?? ((hops.lastIndex(where: { $0.address != nil }) ?? -1) + 1)
        let list = hops.prefix(shown).enumerated().map { index, record -> TraceHop in
            let name = record.address.flatMap { names[$0.s_addr] }
            return TraceHop(
                ttl: index + 1, address: record.address.map(Self.text), hostname: name?.isEmpty == false ? name : nil,
                stats: PingStats.compute(record.samples.values), isDestination: index + 1 == destinationTTL)
        }
        return PathTrace(hops: list, rounds: rounds)
    }

    /// Probes every distance up to the destination once it is known. Until then, all 30 for the first rounds,
    /// then only a few past the farthest router that answered, so a destination that ignores ICMP costs little.
    private func probeLimit() -> Int {
        if let destinationTTL { return destinationTTL }
        guard rounds > 3, let farthest = hops.lastIndex(where: { $0.address != nil }) else { return Self.maxHops }
        return min(Self.maxHops, farthest + 1 + 3)
    }

    // MARK: - Socket

    private func ensureSocket() -> Bool {
        if socketFD >= 0 { return true }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return false }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { close(fd) }
        source.resume()
        socketFD = fd
        readSource = source
        return true
    }

    private func send(ttl: Int, to addr: in_addr) {
        var value = Int32(ttl)
        guard setsockopt(socketFD, IPPROTO_IP, IP_TTL, &value, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            return
        }
        sequence &+= 1
        let seq = sequence
        let packet = ICMPPacket.echoRequest(identifier: identifier, sequence: seq)
        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_family = sa_family_t(AF_INET)
        sa.sin_addr = addr
        let sentAt = Self.now()
        let sent = packet.withUnsafeBytes { buf in
            withUnsafePointer(to: &sa) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketFD, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent == packet.count {
            pending[seq] = (ttl, sentAt)
        } else {
            hops[ttl - 1].samples.append(PingStats.lost)
        }
    }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 512)
        var from = sockaddr_in()
        while true {
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = buffer.withUnsafeMutableBytes { buf in
                withUnsafeMutablePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(socketFD, buf.baseAddress, buf.count, 0, $0, &fromLength)
                    }
                }
            }
            guard n > 0 else { break }
            let now = Self.now()
            let parsed = buffer.withUnsafeBytes {
                ICMPPacket.parseResponse(UnsafeRawBufferPointer(rebasing: $0[0..<n]))
            }
            guard let response = parsed, response.identifier == identifier,
                let probe = pending.removeValue(forKey: response.sequence), probe.ttl <= hops.count
            else { continue }
            record(probe: probe, kind: response.kind, from: from.sin_addr, now: now)
        }
    }

    private func record(
        probe: (ttl: Int, sentAt: UInt64), kind: ICMPPacket.ResponseKind, from: in_addr, now: UInt64
    ) {
        let ms = Float(Double(now - probe.sentAt) / 1_000_000)
        var ttl = probe.ttl
        if kind == .echoReply {
            // Probes sent with a larger TTL than needed reach the destination too; they count as its samples.
            if destinationTTL == nil || ttl < (destinationTTL ?? ttl) {
                destinationTTL = ttl
                if hops.count > ttl { hops.removeSubrange(ttl...) }
            }
            ttl = destinationTTL ?? ttl
        } else if let destinationTTL, ttl >= destinationTTL {
            return
        }
        hops[ttl - 1].address = from
        hops[ttl - 1].samples.append(ms)
        if resolvesNames { lookUpName(from) }
    }

    private func expire(now: UInt64) {
        for (seq, probe) in pending where now - probe.sentAt >= timeoutNanos {
            pending[seq] = nil
            // Probes past the destination never get their own row.
            let ttl = min(probe.ttl, destinationTTL ?? probe.ttl)
            if probe.ttl == ttl, ttl <= hops.count { hops[ttl - 1].samples.append(PingStats.lost) }
        }
    }

    // MARK: - Names

    /// getaddrinfo blocks, so it runs off `queue`.
    private func resolve(_ host: String) {
        guard !resolving else { return }
        resolving = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var hints = addrinfo(
                ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_DGRAM, ai_protocol: 0,
                ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var result: UnsafeMutablePointer<addrinfo>?
            var resolved: in_addr?
            if getaddrinfo(host, nil, &hints, &result) == 0, let info = result, let sa = info.pointee.ai_addr {
                resolved = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            }
            if let result { freeaddrinfo(result) }
            guard let self else { return }
            self.queue.async {
                self.resolving = false
                if self.host == host { self.destination = resolved }
            }
        }
    }

    /// Reverse DNS through the system resolver, once per address. It often names the ISP ("…fibertel.com.ar").
    private func lookUpName(_ addr: in_addr) {
        let key = addr.s_addr
        guard names[key] == nil, !lookingUp.contains(key) else { return }
        lookingUp.insert(key)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var sa = sockaddr_in()
            sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sa.sin_family = sa_family_t(AF_INET)
            sa.sin_addr = addr
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = withUnsafePointer(to: &sa) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getnameinfo(
                        $0, socklen_t(MemoryLayout<sockaddr_in>.size), &name, socklen_t(name.count), nil, 0,
                        NI_NAMEREQD)
                }
            }
            let hostname = rc == 0 ? String(cString: name) : ""
            guard let self else { return }
            self.queue.async {
                self.lookingUp.remove(key)
                self.names[key] = hostname  // "" means "no name", so it is not asked again
            }
        }
    }

    static func text(_ addr: in_addr) -> String {
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var copy = addr
        guard inet_ntop(AF_INET, &copy, &buffer, socklen_t(buffer.count)) != nil else { return "" }
        return String(cString: buffer)
    }

    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}
