/// A trace summarized into the five places a connection goes through: this Mac, the router, the ISP, the
/// internet and the server. Shows where latency or loss starts rather than every router.
public struct NetworkPath: Sendable, Equatable {
    public enum Stage: Int, CaseIterable, Sendable, Comparable {
        case mac, router, isp, internet, server

        public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Segment: Sendable, Equatable, Identifiable {
        public var id: Stage { stage }
        public var stage: Stage
        /// The routers in this stretch, in order. Empty for the Mac.
        public var hops: [TraceHop]
        /// Organization guessed from reverse DNS, e.g. "Fibertel" for the ISP.
        public var name: String?
        /// Round trip from this Mac to the end of this stretch.
        public var latencyMs: Float?
        public var lossFraction: Float?
        /// Nil while there is nothing to judge (no router here answered).
        public var level: HealthLevel?
        /// What raised `level`, when it isn't `.ok`.
        public var isLoss: Bool
    }

    public enum Verdict: Sendable, Equatable {
        case tracing
        case healthy
        case slow(Stage)
        case losing(Stage)
        /// The destination doesn't answer at all.
        case noReply
    }

    public var segments: [Segment]
    public var verdict: Verdict

    public subscript(stage: Stage) -> Segment { segments[stage.rawValue] }

    /// Latency budget for the round trip up to each stage: a Wi-Fi hop should take a few milliseconds,
    /// the whole path uses the ping thresholds.
    public static func latencyLimits(_ stage: Stage, _ thresholds: Thresholds) -> (warning: Float, critical: Float) {
        switch stage {
        case .mac, .router: return (20, 80)
        case .isp: return (50, 120)
        case .internet, .server: return (thresholds.pingWarningMs, thresholds.pingCriticalMs)
        }
    }

    public init(trace: PathTrace?, thresholds: Thresholds = Thresholds()) {
        let hops = trace?.hops ?? []
        let groups = Self.group(hops)
        let effective = Self.effective(hops)
        var segments: [Segment] = []
        for stage in Stage.allCases {
            let members = groups[stage] ?? []
            var segment = Segment(
                stage: stage, hops: members, name: nil, latencyMs: nil, lossFraction: nil, level: nil, isLoss: false)
            if stage == .mac {
                segment.level = trace == nil ? nil : .ok
            } else if stage == .isp {
                let firstPublic = members.first(where: { !$0.isSilent && !Self.isPrivate($0.address) })
                segment.name = Self.organization(firstPublic?.hostname)?.name
            }
            if let last = members.last(where: { !$0.isSilent }), let value = effective[last.ttl] {
                segment.latencyMs = value.latency
                segment.lossFraction = value.loss
                let limits = Self.latencyLimits(stage, thresholds)
                let latency = value.latency ?? 0
                let loss = value.loss
                var latencyLevel = HealthLevel.ok
                if latency > limits.critical {
                    latencyLevel = .critical
                } else if latency > limits.warning {
                    latencyLevel = .warning
                }
                var lossLevel = HealthLevel.ok
                if loss > thresholds.pingLossCritical {
                    lossLevel = .critical
                } else if loss > thresholds.pingLossWarning {
                    lossLevel = .warning
                }
                segment.level = max(latencyLevel, lossLevel)
                segment.isLoss = lossLevel >= latencyLevel && lossLevel != .ok
            }
            segments.append(segment)
        }
        // A destination that never answered after a few rounds is a problem, not missing data.
        let rounds = trace?.rounds ?? 0
        let reached = trace?.reachedDestination == true
        if !reached && rounds >= 3 {
            segments[Stage.server.rawValue].level = .critical
            segments[Stage.server.rawValue].isLoss = true
            segments[Stage.server.rawValue].lossFraction = 1
        }
        self.segments = segments

        if trace == nil || (rounds < 2 && !reached) {
            verdict = .tracing
        } else if let first = segments.first(where: { ($0.level ?? .ok) != .ok }) {
            if first.stage == .server && !reached {
                verdict = .noReply
            } else {
                verdict = first.isLoss ? .losing(first.stage) : .slow(first.stage)
            }
        } else {
            verdict = .healthy
        }
    }

    // MARK: - Grouping

    /// Hop 1 is the router; then the ISP runs while hops are private (ISP-internal or carrier-grade NAT)
    /// up to the first public hop, and on while later hops share that hop's domain; the rest is the internet.
    static func group(_ hops: [TraceHop]) -> [Stage: [TraceHop]] {
        var groups: [Stage: [TraceHop]] = [:]
        if let destination = hops.last, destination.isDestination { groups[.server] = [destination] }
        let routers = hops.filter { !$0.isDestination }
        guard let first = routers.first, first.ttl == 1 else {
            groups[.internet] = routers
            return groups
        }
        groups[.router] = [first]
        var ispEnd = 1
        var seenPublic = false
        var domain: String?
        for index in routers.indices.dropFirst() {
            let hop = routers[index]
            if hop.isSilent { continue }
            let isPrivate = Self.isPrivate(hop.address)
            if !seenPublic {
                if !isPrivate {
                    seenPublic = true
                    domain = organization(hop.hostname)?.domain
                }
            } else if !isPrivate && (domain == nil || organization(hop.hostname)?.domain != domain) {
                break
            }
            ispEnd = index + 1
        }
        groups[.isp] = Array(routers[1..<ispEnd])
        groups[.internet] = Array(routers[ispEnd...])
        return groups
    }

    /// Latency and loss as they reach each hop, keyed by TTL. Routers answer traceroute probes at low priority,
    /// so a hop can look slow or lossy while traffic through it is fine; as MTR users do, a hop is only judged
    /// as bad as the best hop at or after it.
    static func effective(_ hops: [TraceHop]) -> [Int: (latency: Float?, loss: Float)] {
        var result: [Int: (latency: Float?, loss: Float)] = [:]
        var bestLatency: Float?
        var bestLoss: Float?
        for hop in hops.reversed() where !hop.isSilent {
            if let average = hop.stats.averageMs { bestLatency = min(bestLatency ?? average, average) }
            bestLoss = min(bestLoss ?? hop.stats.lossFraction, hop.stats.lossFraction)
            result[hop.ttl] = (bestLatency, bestLoss ?? 0)
        }
        return result
    }

    // MARK: - Addresses and names

    /// Private (RFC 1918), carrier-grade NAT (RFC 6598) and link-local IPv4 addresses.
    static func isPrivate(_ address: String?) -> Bool {
        guard let address else { return false }
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168), (169, 254): return true
        case (172, 16...31), (100, 64...127): return true
        default: return false
        }
    }

    /// Carrier-grade NAT (RFC 6598): addresses an ISP uses inside its own network.
    static func isCarrierNAT(_ address: String?) -> Bool {
        guard let parts = address?.split(separator: ".").compactMap({ Int($0) }), parts.count == 4 else {
            return false
        }
        return parts[0] == 100 && (64...127).contains(parts[1])
    }

    /// The first router of the internet provider: past this Mac's own router (and any other home router
    /// behind it, which has a private address), the first one with a public or carrier-grade NAT address.
    static func ispHop(in hops: [TraceHop], gateway: String?) -> String? {
        for hop in hops where hop.ttl >= 2 && !hop.isDestination {
            guard let address = hop.address, address != gateway else { continue }
            if !isPrivate(address) || isCarrierNAT(address) { return address }
        }
        return nil
    }

    private static let secondLevel: Set<String> = [
        "com", "net", "org", "co", "gov", "gob", "edu", "ac", "ne", "or", "mil", "int",
    ]

    /// The registrable domain of a router's name and a display name for it:
    /// "host-1.static.fibertel.com.ar" → ("fibertel.com.ar", "Fibertel"), "ae1.att.net" → ("att.net", "ATT").
    static func organization(_ hostname: String?) -> (domain: String, name: String)? {
        guard let hostname else { return nil }
        let labels = hostname.lowercased().split(separator: ".").map(String.init)
        guard labels.count >= 2, labels.last?.allSatisfy(\.isLetter) == true else { return nil }
        var size = 2
        if labels.count >= 3, labels[labels.count - 1].count == 2, secondLevel.contains(labels[labels.count - 2]) {
            size = 3
        }
        guard labels.count >= size else { return nil }
        let domainLabels = labels.suffix(size)
        let label = domainLabels.first ?? ""
        guard !label.isEmpty else { return nil }
        let name = label.count <= 3 ? label.uppercased() : label.prefix(1).uppercased() + label.dropFirst()
        return (domainLabels.joined(separator: "."), name)
    }
}
