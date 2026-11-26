import Darwin

enum Gateway {
    /// Default IPv4 gateway from the routing table (no subprocess, one sysctl).
    static func defaultIPv4() -> in_addr? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_GATEWAY]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }

        return buffer.withUnsafeBytes { raw -> in_addr? in
            var offset = 0
            let headerSize = MemoryLayout<rt_msghdr>.size
            var scopedFallback: in_addr?
            while offset + headerSize <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
                let messageLength = Int(header.rtm_msglen)
                guard messageLength > 0 else { break }
                defer { offset += messageLength }

                let addrs = header.rtm_addrs
                guard addrs & RTA_DST != 0, addrs & RTA_GATEWAY != 0 else { continue }
                var cursor = offset + headerSize
                guard cursor + MemoryLayout<sockaddr_in>.size <= offset + messageLength else { continue }
                let dst = raw.loadUnaligned(fromByteOffset: cursor, as: sockaddr_in.self)
                cursor += roundUp(Int(dst.sin_len))
                guard cursor + MemoryLayout<sockaddr_in>.size <= offset + messageLength else { continue }
                let gw = raw.loadUnaligned(fromByteOffset: cursor, as: sockaddr_in.self)

                guard dst.sin_family == sa_family_t(AF_INET), dst.sin_addr.s_addr == 0,
                    gw.sin_family == sa_family_t(AF_INET), gw.sin_addr.s_addr != 0
                else { continue }
                if header.rtm_flags & Int32(RTF_IFSCOPE) == 0 { return gw.sin_addr }
                if scopedFallback == nil { scopedFallback = gw.sin_addr }
            }
            return scopedFallback
        }
    }

    private static func roundUp(_ len: Int) -> Int {
        len > 0 ? 1 + ((len - 1) | (MemoryLayout<UInt32>.size - 1)) : MemoryLayout<UInt32>.size
    }
}
