import Darwin
import Dispatch

/// Sends one probe per target per `probe()` call and reports RTTs asynchronously.
/// Everything runs on `queue` (serial). No threads are blocked waiting for replies.
public final class PingEngine {
    public let queue: DispatchQueue
    public var targets: [PingTarget] {
        didSet { addresses.removeAll() }
    }
    /// Probes without a reply after this long are reported as lost.
    public var timeoutNanos: UInt64 = 1_000_000_000
    /// Called on `queue` with the target index and RTT in ms, or nil if lost.
    public var onResult: ((Int, Float?) -> Void)?

    private let identifier = UInt16(truncatingIfNeeded: getpid())
    private var sequence: UInt16 = 0
    private var icmpSocket: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var pendingICMP: [UInt16: (target: Int, sentAt: UInt64)] = [:]
    private var pendingTCP: [Int32: (target: Int, sentAt: UInt64, source: DispatchSourceWrite)] = [:]

    private struct CachedAddress { var addr: in_addr; var resolvedAt: UInt64 }
    private var addresses: [Int: CachedAddress] = [:]
    private var resolving: Set<Int> = []
    private let hostTTL: UInt64 = 300 * 1_000_000_000
    private let gatewayTTL: UInt64 = 30 * 1_000_000_000

    public init(targets: [PingTarget], queue: DispatchQueue) {
        self.targets = targets
        self.queue = queue
    }

    private lazy var http = HTTPProber(queue: queue) { [weak self] target, ms in self?.onResult?(target, ms) }

    deinit {
        readSource?.cancel()
        for (_, p) in pendingTCP { p.source.cancel() }
    }

    /// Probe the given target indices. Must be called on `queue`.
    public func probe(_ indices: [Int]) {
        dispatchPrecondition(condition: .onQueue(queue))
        expire(now: Self.now())
        for i in indices where targets.indices.contains(i) {
            if case .https(let path) = targets[i].method {
                http.probe(target: i, host: targets[i].host, path: path)
                continue
            }
            guard let addr = address(for: i) else { continue }
            switch targets[i].method {
            case .icmp: sendICMP(target: i, to: addr)
            case .tcp(let port): connectTCP(target: i, to: addr, port: port)
            case .https: break
            }
        }
    }

    /// Drop sockets and cached addresses (e.g. on sleep or network change).
    public func reset() {
        dispatchPrecondition(condition: .onQueue(queue))
        readSource?.cancel(); readSource = nil; icmpSocket = -1
        for (_, p) in pendingTCP { p.source.cancel() }
        pendingTCP.removeAll()
        pendingICMP.removeAll()
        addresses.removeAll()
        http.reset()
        ispProbe?.stop()
        ispProbe = nil
        isp = nil
    }

    // MARK: - ISP discovery

    /// The provider's first router, found with a short traceroute (see `NetworkPath.ispHop`).
    private struct ISPRouter {
        /// Nil when the trace found none; retried after `ispRetry`.
        var addr: in_addr?
        /// The router this was found behind: a different one means a different network.
        var gateway: UInt32?
        var foundAt: UInt64
        var checkedAt: UInt64
    }
    private var isp: ISPRouter?
    private var ispProbe: Traceroute?
    private let ispTTL: UInt64 = 300 * 1_000_000_000
    private let ispRetry: UInt64 = 60 * 1_000_000_000
    private let ispGatewayCheck: UInt64 = 30 * 1_000_000_000
    /// Any well-connected host works: only the first few routers on the way matter.
    static let ispTraceHost = "1.1.1.1"

    private func ispAddress(now: UInt64) -> in_addr? {
        guard var router = isp else {
            discoverISP()
            return nil
        }
        if now - router.checkedAt >= ispGatewayCheck {
            router.checkedAt = now
            isp = router
            if Gateway.defaultIPv4()?.s_addr != router.gateway {  // joined another network
                isp = nil
                discoverISP()
                return nil
            }
        }
        if now - router.foundAt >= (router.addr == nil ? ispRetry : ispTTL) { discoverISP() }
        return router.addr
    }

    /// Two rounds of TTL-limited probes, then the first provider router that answered. About 60 small
    /// packets every 5 minutes, also with the popover closed, since the ISP row lives in the menu bar alert.
    private func discoverISP() {
        guard ispProbe == nil else { return }
        let gateway = Gateway.defaultIPv4()
        let probe = Traceroute(queue: queue, resolvesNames: false)
        ispProbe = probe
        probe.start(host: Self.ispTraceHost)
        probe.probeRound()
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.ispProbe === probe else { return }
            probe.probeRound()
        }
        queue.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.ispProbe === probe else { return }
            let hops = probe.snapshot()?.hops ?? []
            probe.stop()
            self.ispProbe = nil
            var found: in_addr?
            if let text = NetworkPath.ispHop(in: hops, gateway: gateway.map(Traceroute.text)) {
                var addr = in_addr()
                if inet_pton(AF_INET, text, &addr) == 1 { found = addr }
            }
            let now = Self.now()
            self.isp = ISPRouter(addr: found, gateway: gateway?.s_addr, foundAt: now, checkedAt: now)
        }
    }

    // MARK: - Address resolution

    private func address(for index: Int) -> in_addr? {
        let now = Self.now()
        let target = targets[index]
        if target.isISP { return ispAddress(now: now) }
        if let cached = addresses[index], now - cached.resolvedAt < (target.isGateway ? gatewayTTL : hostTTL) {
            return cached.addr
        }
        if target.isGateway {
            guard let gw = Gateway.defaultIPv4() else { addresses[index] = nil; return nil }
            addresses[index] = CachedAddress(addr: gw, resolvedAt: now)
            return gw
        }
        var literal = in_addr()
        if inet_pton(AF_INET, target.host, &literal) == 1 {
            addresses[index] = CachedAddress(addr: literal, resolvedAt: now)
            return literal
        }
        resolveAsync(index: index, host: target.host)
        return addresses[index]?.addr  // stale value while re-resolving, if any
    }

    /// getaddrinfo blocks, so it runs off the sampling queue.
    private func resolveAsync(index: Int, host: String) {
        guard !resolving.contains(index) else { return }
        resolving.insert(index)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var hints = addrinfo(
                ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var result: UnsafeMutablePointer<addrinfo>?
            var resolved: in_addr?
            if getaddrinfo(host, nil, &hints, &result) == 0, let info = result, let sa = info.pointee.ai_addr {
                resolved = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            }
            if let result { freeaddrinfo(result) }
            guard let self else { return }
            self.queue.async {
                self.resolving.remove(index)
                if let resolved, self.targets.indices.contains(index), self.targets[index].host == host {
                    self.addresses[index] = CachedAddress(addr: resolved, resolvedAt: Self.now())
                }
            }
        }
    }

    // MARK: - ICMP

    private func ensureICMPSocket() -> Bool {
        if icmpSocket >= 0 { return true }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return false }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drainICMP() }
        source.setCancelHandler { close(fd) }
        source.resume()
        icmpSocket = fd
        readSource = source
        return true
    }

    private func sendICMP(target: Int, to addr: in_addr) {
        guard ensureICMPSocket() else { return }
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
                    sendto(icmpSocket, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent == packet.count {
            pendingICMP[seq] = (target, sentAt)
        } else {
            onResult?(target, nil)  // e.g. no route: count as lost
        }
    }

    private func drainICMP() {
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let n = buffer.withUnsafeMutableBytes { recv(icmpSocket, $0.baseAddress, $0.count, 0) }
            guard n > 0 else { break }
            let now = Self.now()
            let parsed = buffer.withUnsafeBytes {
                ICMPPacket.parseEchoReply(UnsafeRawBufferPointer(rebasing: $0[0..<n]))
            }
            guard let reply = parsed, reply.identifier == identifier,
                let pending = pendingICMP.removeValue(forKey: reply.sequence)
            else { continue }
            onResult?(pending.target, Float(Double(now - pending.sentAt) / 1_000_000))
        }
    }

    // MARK: - TCP

    private func connectTCP(target: Int, to addr: in_addr, port: UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_family = sa_family_t(AF_INET)
        sa.sin_port = port.bigEndian
        sa.sin_addr = addr
        let sentAt = Self.now()
        let rc = withUnsafePointer(to: &sa) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc != 0 && errno != EINPROGRESS {
            close(fd)
            onResult?(target, nil)
            return
        }
        let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.finishTCP(fd: fd) }
        source.setCancelHandler { close(fd) }
        pendingTCP[fd] = (target, sentAt, source)
        source.resume()
    }

    private func finishTCP(fd: Int32) {
        guard let pending = pendingTCP.removeValue(forKey: fd) else { return }
        let now = Self.now()
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        pending.source.cancel()
        // A refused connection still completed a round trip.
        let ok = err == 0 || err == ECONNREFUSED
        onResult?(pending.target, ok ? Float(Double(now - pending.sentAt) / 1_000_000) : nil)
    }

    // MARK: - Timeouts

    private func expire(now: UInt64) {
        for (seq, p) in pendingICMP where now - p.sentAt >= timeoutNanos {
            pendingICMP[seq] = nil
            onResult?(p.target, nil)
        }
        for (fd, p) in pendingTCP where now - p.sentAt >= timeoutNanos {
            pendingTCP[fd] = nil
            p.source.cancel()
            onResult?(p.target, nil)
        }
    }

    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}
