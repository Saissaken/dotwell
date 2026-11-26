import Darwin
import SystemConfiguration

/// The DNS server macOS uses, as `scutil --dns` lists it first. One call to `configd`, no subprocess.
public enum DNSServer {
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

    /// Tailscale's MagicDNS answers on this fixed address on every Mac in a tailnet.
    static let tailscale = "100.100.100.100"

    /// Well-known resolvers, so the row says "DNS Cloudflare" instead of an address.
    static let knownProviders: [String: String] = [
        "1.1.1.1": "Cloudflare", "1.0.0.1": "Cloudflare", "1.1.1.2": "Cloudflare", "1.0.0.2": "Cloudflare",
        "1.1.1.3": "Cloudflare", "1.0.0.3": "Cloudflare",
        "8.8.8.8": "Google", "8.8.4.4": "Google",
        "9.9.9.9": "Quad9", "149.112.112.112": "Quad9", "9.9.9.10": "Quad9", "149.112.112.10": "Quad9",
        "9.9.9.11": "Quad9", "149.112.112.11": "Quad9", "9.9.9.12": "Quad9", "149.112.112.12": "Quad9",
        "208.67.222.222": "OpenDNS", "208.67.220.220": "OpenDNS", "208.67.222.123": "OpenDNS",
        "208.67.220.123": "OpenDNS",
        "94.140.14.14": "AdGuard", "94.140.15.15": "AdGuard", "94.140.14.15": "AdGuard", "94.140.15.16": "AdGuard",
        "94.140.14.140": "AdGuard", "94.140.14.141": "AdGuard",
        DNSServer.tailscale: "Tailscale",
    ]

    /// Providers that give each account its own address inside a block of theirs.
    static let knownPrefixes: [(prefix: String, provider: String)] = [
        ("45.90.28.", "NextDNS"), ("45.90.30.", "NextDNS"),
        ("76.76.2.", "Control D"), ("76.76.10.", "Control D"),
        ("194.242.2.", "Mullvad"),
        ("185.228.168.", "CleanBrowsing"), ("185.228.169.", "CleanBrowsing"),
        ("127.", "This Mac"),
    ]

    /// A short name for a resolver: its provider, "Router" when the router itself resolves names (common at
    /// home), "This Mac" for a resolver running locally, or nil when it is none of those.
    public static func name(of address: String, routerAddress: String?) -> String? {
        if let provider = knownProviders[address] { return provider }
        if address == routerAddress { return "Router" }
        return knownPrefixes.first { address.hasPrefix($0.prefix) }?.provider
    }

    /// "Router (192.168.1.1)", or just the address when the resolver has no name.
    public static func label(of address: String, routerAddress: String?) -> String {
        name(of: address, routerAddress: routerAddress).map { "\($0) (\(address))" } ?? address
    }
}

extension PingTargetState {
    /// The row's name. For the DNS row it says which server answers ("DNS Cloudflare", "DNS Router"), or just
    /// "DNS" when the server has no name: its address is in the row's detail, so the row never truncates.
    public func displayName(routerAddress: String?) -> String {
        guard target.isDNS, let address, let name = DNSServer.name(of: address, routerAddress: routerAddress)
        else { return target.name }
        return "DNS \(name)"
    }
}
