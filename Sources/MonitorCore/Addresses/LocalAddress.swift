import Darwin
import SystemConfiguration

/// The kind of link the Mac reaches the network through.
public enum InterfaceKind: Sendable, Equatable {
    case wifi
    case ethernet
    case cellular
    case vpn
    case other
}

/// The Mac's address on the local network, for the interface that carries the default route.
public struct LocalAddress: Sendable, Equatable {
    /// BSD name, such as `en0`.
    public var interface: String
    public var kind: InterfaceKind
    public var ipv4: String

    public init(interface: String, kind: InterfaceKind, ipv4: String) {
        self.interface = interface
        self.kind = kind
        self.ipv4 = ipv4
    }
}

enum LocalAddressReader {
    /// Reads the IPv4 address of the default route's interface: one sysctl and one `getifaddrs`,
    /// no subprocess. Falls back to the first `en*` interface with an address.
    static func read() -> LocalAddress? {
        let preferred = Gateway.defaultIPv4Route().flatMap { interfaceName(index: $0.interfaceIndex) }
        let candidates = ipv4Addresses()
        guard
            let pick = candidates.first(where: { $0.interface == preferred })
                ?? candidates.first(where: { $0.interface.hasPrefix("en") })
        else { return nil }
        return LocalAddress(interface: pick.interface, kind: kind(of: pick.interface), ipv4: pick.address)
    }

    /// IPv4 addresses of interfaces that are up and running, skipping loopback and link-local (169.254/16).
    static func ipv4Addresses() -> [(interface: String, address: String)] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        var result: [(interface: String, address: String)] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let addr = entry.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0
            else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            guard !isLinkLocal(ip), let text = format(ip) else { continue }
            result.append((String(cString: entry.pointee.ifa_name), text))
        }
        return result
    }

    static func isLinkLocal(_ address: in_addr) -> Bool {
        let host = UInt32(bigEndian: address.s_addr)
        return host >> 16 == 0xA9FE  // 169.254.0.0/16
    }

    static func format(_ address: in_addr) -> String? {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return String(cString: buffer)
    }

    private static func interfaceName(index: UInt32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        guard if_indextoname(index, &buffer) != nil else { return nil }
        return String(cString: buffer)
    }

    /// Tunnels are recognised by name; everything else by the type System Settings knows it as.
    static func kind(of interface: String) -> InterfaceKind {
        if ["utun", "ipsec", "ppp", "tun", "tap"].contains(where: { interface.hasPrefix($0) }) { return .vpn }
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return .other }
        guard let match = all.first(where: { SCNetworkInterfaceGetBSDName($0) as String? == interface }),
            let type = SCNetworkInterfaceGetInterfaceType(match) as String?
        else { return .other }
        if type == kSCNetworkInterfaceTypeIEEE80211 as String { return .wifi }
        if type == kSCNetworkInterfaceTypeEthernet as String { return .ethernet }
        if type == kSCNetworkInterfaceTypeWWAN as String { return .cellular }
        return .other
    }
}
