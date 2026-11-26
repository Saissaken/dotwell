import Foundation
import SystemConfiguration

/// Every DNS resolver macOS has, and the servers each lookup goes to first: what `scutil --dns` shows, read
/// from `configd` in one call. Read only when the DNS row's detail opens, so it costs nothing otherwise.
public struct DNSSetup: Equatable, Sendable {
    /// The resolver one network service (Wi-Fi, Ethernet, a VPN) asked for.
    public struct Resolver: Equatable, Sendable {
        /// The service's name in System Settings, e.g. "Wi-Fi"; nil for VPN apps that have none.
        public var source: String?
        /// The network interface, e.g. "en0" or "utun4".
        public var interface: String?
        public var isVPN: Bool
        /// Servers typed in System Settings rather than handed out by the network.
        public var isManual: Bool
        public var servers: [String]
        /// The only domains this resolver answers (a VPN's company or tailnet domains). Empty when it answers
        /// everything.
        public var matchDomains: [String]

        public init(
            source: String?, interface: String?, isVPN: Bool, isManual: Bool = false, servers: [String],
            matchDomains: [String] = []
        ) {
            self.source = source
            self.interface = interface
            self.isVPN = isVPN
            self.isManual = isManual
            self.servers = servers
            self.matchDomains = matchDomains
        }
    }

    /// The servers every lookup goes to first, in order: the system's default resolver.
    public var servers: [String]
    public var resolvers: [Resolver]

    public init(servers: [String], resolvers: [Resolver]) {
        self.servers = servers
        self.resolvers = resolvers
    }

    public static func current() -> DNSSetup? {
        guard let store = SCDynamicStoreCreate(nil, "Dotwell" as CFString, nil, nil) else { return nil }
        let patterns = [
            "State:/Network/Service/[^/]+/DNS", "Setup:/Network/Service/[^/]+/DNS",
            "State:/Network/Service/[^/]+/IPv4", "Setup:/Network/Service/[^/]+",
            "Setup:/Network/Service/[^/]+/Interface",
        ]
        let keys = ["State:/Network/Global/DNS"] as CFArray
        guard let values = SCDynamicStoreCopyMultiple(store, keys, patterns as CFArray) as? [String: Any] else {
            return nil
        }
        return parse(values)
    }

    /// Builds the setup from `configd`'s keys and values. Servers typed in System Settings (Setup:) win over
    /// the network's (State:), as they do for macOS itself.
    static func parse(_ values: [String: Any]) -> DNSSetup {
        func dict(_ key: String) -> [String: Any]? { values[key] as? [String: Any] }
        let global = dict("State:/Network/Global/DNS")?["ServerAddresses"] as? [String] ?? []
        var ids = Set<String>()
        for key in values.keys where key.hasSuffix("/DNS") && key.contains(":/Network/Service/") {
            let parts = key.split(separator: "/")
            if parts.count == 5 { ids.insert(String(parts[3])) }
        }
        let resolvers = ids.sorted().compactMap { id -> Resolver? in
            let state = dict("State:/Network/Service/\(id)/DNS")
            let setup = dict("Setup:/Network/Service/\(id)/DNS")
            let typed = setup?["ServerAddresses"] as? [String] ?? []
            let servers = typed.isEmpty ? state?["ServerAddresses"] as? [String] ?? [] : typed
            guard !servers.isEmpty else { return nil }
            let service = dict("Setup:/Network/Service/\(id)")
            let link = dict("Setup:/Network/Service/\(id)/Interface")
            let interface =
                dict("State:/Network/Service/\(id)/IPv4")?["InterfaceName"] as? String ?? link?["DeviceName"] as? String
            let domains = (state?["SupplementalMatchDomains"] as? [String] ?? []).filter { !$0.isEmpty }
            return Resolver(
                source: service?["UserDefinedName"] as? String ?? link?["UserDefinedName"] as? String,
                interface: interface,
                isVPN: service == nil || isTunnel(interface),
                isManual: !typed.isEmpty, servers: servers, matchDomains: domains)
        }
        return DNSSetup(servers: global, resolvers: resolvers)
    }

    static func isTunnel(_ interface: String?) -> Bool {
        guard let interface else { return false }
        return ["utun", "ipsec", "ppp", "tun", "tap", "wg"].contains { interface.hasPrefix($0) }
    }
}

/// The DNS row's detail, worked out from a `DNSSetup`: who set the server that answers, the network's own
/// server when something else took over, and the domains that go elsewhere.
public struct DNSChain: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var label: String
        public var value: String
    }

    public var lines: [Line] = []
    /// One sentence on what is going on, when there is more than one server in play.
    public var summary: String?

    /// - Parameters:
    ///   - address: the server the row measures, the first IPv4 server of the default resolver.
    ///   - routerAddress: the router's address, so a router that resolves names is called "Router".
    public init(setup: DNSSetup, answering address: String, routerAddress: String?) {
        func label(_ server: String) -> String { DNSServer.label(of: server, routerAddress: routerAddress) }
        let defaults = setup.resolvers.filter { $0.matchDomains.isEmpty }
        // A VPN that takes over DNS may also list its own domains, so fall back to any resolver with the server.
        let owner =
            defaults.first { $0.servers.contains(address) } ?? setup.resolvers.first { $0.servers.contains(address) }
        let ownerName = owner.map { Self.name(of: $0, answering: address) }
        if let owner, let ownerName {
            let how = owner.isVPN ? "VPN" : owner.isManual ? "set by hand" : "from the network"
            lines.append(Line(label: "Set by", value: "\(ownerName) (\(how))"))
        }

        let backups = setup.servers.filter { $0 != address && $0.contains(".") }
        if !backups.isEmpty {
            lines.append(Line(label: "Backup", value: backups.prefix(3).map(label).joined(separator: ", ")))
        }

        // The network's own servers, when something else answers instead.
        let network = defaults.filter { !$0.isVPN && $0 != owner && !$0.servers.contains(address) }
        let networkServers = Self.unique(network.flatMap(\.servers).filter { $0.contains(".") })
        if !networkServers.isEmpty {
            lines.append(Line(label: "Network", value: networkServers.prefix(2).map(label).joined(separator: ", ")))
        }

        var special: [String] = []
        for resolver in setup.resolvers where !resolver.matchDomains.isEmpty {
            let domains = resolver.matchDomains.filter { !$0.hasSuffix(".arpa") }
            guard !domains.isEmpty, let server = resolver.servers.first else { continue }
            let shown = domains.prefix(2).joined(separator: ", ") + (domains.count > 2 ? " +\(domains.count - 2)" : "")
            let name = DNSServer.name(of: server, routerAddress: routerAddress) ?? resolver.source ?? server
            special.append("\(shown) → \(name)")
        }
        if !special.isEmpty {
            lines.append(Line(label: "Domains", value: special.prefix(3).joined(separator: "\n")))
        }

        if let owner, owner.isVPN, let ownerName {
            if address == DNSServer.tailscale {
                summary =
                    "Tailscale is handling your Mac's DNS. It answers names on your tailnet and passes the rest on, "
                    + "usually to your network's DNS."
            } else {
                summary = "\(ownerName) is handling your Mac's DNS while it is connected."
            }
        } else if owner == nil, !networkServers.isEmpty {
            summary =
                address.hasPrefix("127.")
                ? "An app on this Mac is handling its DNS, instead of your network's server."
                : "Something other than your network, like a VPN or a filtering app, is handling your Mac's DNS."
        } else if !special.isEmpty {
            summary = "Lookups go to \(label(address)). The domains listed go to their own server."
        }
    }

    /// "Tailscale", "Wi-Fi", or "A VPN" when a VPN app left its service unnamed.
    static func name(of resolver: DNSSetup.Resolver, answering address: String) -> String {
        if let source = resolver.source { return source }
        if resolver.isVPN { return address == DNSServer.tailscale ? "Tailscale" : "A VPN" }
        return resolver.interface ?? "Your network"
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// When the DNS server changed by itself, e.g. a VPN connecting, so the row can say why its number moved.
public struct DNSChange: Equatable, Sendable {
    public var previous: String
    public var at: Date

    public init(previous: String, at: Date) {
        self.previous = previous
        self.at = at
    }
}

/// Follows the DNS row's address between ticks. The address is already re-read every 30 s to probe it, so
/// noticing a change costs nothing extra.
struct DNSChangeTracker {
    private(set) var last: String?
    private(set) var change: DNSChange?

    /// A missing address (no network) is not a change: the next one is compared with the one before it.
    mutating func observe(_ address: String?, now: Date) {
        guard let address else { return }
        if let last, last != address { change = DNSChange(previous: last, at: now) }
        last = address
    }
}
