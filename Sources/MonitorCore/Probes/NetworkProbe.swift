import Darwin

/// Cumulative bytes over all physical-ish interfaces (excludes loopback and point-to-point/VPN tunnels
/// so VPN traffic is not counted twice).
public struct NetworkCounters: Equatable, Sendable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received; self.sent = sent
    }

    /// Bits per second between two readings. A counter that went backwards (interface reset) yields 0.
    public static func rates(from old: NetworkCounters, to new: NetworkCounters, seconds: Double) -> (
        down: Double, up: Double
    ) {
        guard seconds > 0 else { return (0, 0) }
        let rx = new.received >= old.received ? new.received - old.received : 0
        let tx = new.sent >= old.sent ? new.sent - old.sent : 0
        return (Double(rx) * 8 / seconds, Double(tx) * 8 / seconds)
    }
}

/// Reads 64-bit interface counters via `sysctl(NET_RT_IFLIST2)`.
/// (`getifaddrs` exposes 32-bit counters that wrap every 4 GB.)
public final class NetworkProbe {
    private var buffer = [UInt8]()

    public init() {}

    public func sample() -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        if buffer.count < length { buffer = [UInt8](repeating: 0, count: length + 1024) }
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            let headerSize = MemoryLayout<if_msghdr>.size
            while offset + headerSize <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                    offset + MemoryLayout<if_msghdr2>.size <= length
                {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let flags = Int32(info.ifm_flags)
                    let excluded =
                        (flags & IFF_LOOPBACK) != 0 || (flags & IFF_POINTOPOINT) != 0 || (flags & IFF_UP) == 0
                    if !excluded {
                        rx &+= info.ifm_data.ifi_ibytes
                        tx &+= info.ifm_data.ifi_obytes
                    }
                }
                offset += messageLength
            }
        }
        return NetworkCounters(received: rx, sent: tx)
    }
}
