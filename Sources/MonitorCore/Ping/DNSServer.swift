import Darwin
import SystemConfiguration

/// The DNS server macOS uses, as `scutil --dns` lists it first. One call to `configd`, no subprocess.
enum DNSServer {
    /// The first IPv4 server of the system's default resolver, or nil when it only has IPv6 servers or none.
    static func primaryIPv4() -> in_addr? {
        guard let store = SCDynamicStoreCreate(nil, "Dotwell" as CFString, nil, nil),
            let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
            let servers = value["ServerAddresses"] as? [String]
        else { return nil }
        return firstIPv4(servers)
    }

    static func firstIPv4(_ servers: [String]) -> in_addr? {
        for server in servers {
            var addr = in_addr()
            if inet_pton(AF_INET, server, &addr) == 1 { return addr }
        }
        return nil
    }

    /// Well-known public resolvers, so the row says "DNS Cloudflare" instead of an address.
    static let knownProviders: [String: String] = [
        "1.1.1.1": "Cloudflare", "1.0.0.1": "Cloudflare", "1.1.1.2": "Cloudflare", "1.0.0.2": "Cloudflare",
        "1.1.1.3": "Cloudflare", "1.0.0.3": "Cloudflare",
        "8.8.8.8": "Google", "8.8.4.4": "Google",
        "9.9.9.9": "Quad9", "149.112.112.112": "Quad9",
        "208.67.222.222": "OpenDNS", "208.67.220.220": "OpenDNS",
        "94.140.14.14": "AdGuard", "94.140.15.15": "AdGuard",
    ]
}

extension PingTargetState {
    /// The row's name. For the DNS row it says which server answers: a known provider, "Router" when the
    /// router itself resolves names (common at home), or the server's address.
    public func displayName(routerAddress: String?) -> String {
        guard target.isDNS, let address else { return target.name }
        if let provider = DNSServer.knownProviders[address] { return "DNS \(provider)" }
        if address == routerAddress { return "DNS Router" }
        return "DNS \(address)"
    }
}
