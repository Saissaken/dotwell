import Darwin

/// Minimal ICMP echo encoding/decoding.
enum ICMPPacket {
    static let echoRequest: UInt8 = 8
    static let echoReply: UInt8 = 0
    static let destinationUnreachable: UInt8 = 3
    static let timeExceeded: UInt8 = 11
    static let headerSize = 8
    static let payloadSize = 8

    static func echoRequest(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: headerSize + payloadSize)
        p[0] = echoRequest
        p[4] = UInt8(identifier >> 8); p[5] = UInt8(identifier & 0xff)
        p[6] = UInt8(sequence >> 8); p[7] = UInt8(sequence & 0xff)
        let sum = checksum(p)
        p[2] = UInt8(sum >> 8); p[3] = UInt8(sum & 0xff)
        return p
    }

    /// Internet checksum (RFC 1071) over big-endian 16-bit words.
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < bytes.count {
            sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum)
    }

    /// Parses an echo reply. On macOS, datagram ICMP sockets deliver the IPv4 header too; it is skipped if present.
    static func parseEchoReply(_ bytes: UnsafeRawBufferPointer) -> (identifier: UInt16, sequence: UInt16)? {
        guard bytes.count >= headerSize else { return nil }
        var offset = 0
        if bytes[0] >> 4 == 4 {
            offset = Int(bytes[0] & 0x0f) * 4
        }
        guard bytes.count >= offset + headerSize, bytes[offset] == echoReply else { return nil }
        let id = UInt16(bytes[offset + 4]) << 8 | UInt16(bytes[offset + 5])
        let seq = UInt16(bytes[offset + 6]) << 8 | UInt16(bytes[offset + 7])
        return (id, seq)
    }

    /// What came back for one of our echo requests.
    enum ResponseKind: Equatable {
        /// The destination answered.
        case echoReply
        /// A router on the way dropped the probe because its TTL ran out.
        case timeExceeded
        /// A router or the destination could not deliver the probe.
        case unreachable
    }

    /// Parses an echo reply, or an ICMP error that quotes one of our echo requests (RFC 792: the error carries
    /// the original IPv4 header and the first 8 bytes of the original datagram, which hold our id and sequence).
    static func parseResponse(
        _ bytes: UnsafeRawBufferPointer
    ) -> (kind: ResponseKind, identifier: UInt16, sequence: UInt16)? {
        guard bytes.count >= headerSize else { return nil }
        let offset = bytes[0] >> 4 == 4 ? Int(bytes[0] & 0x0f) * 4 : 0
        guard bytes.count >= offset + headerSize else { return nil }
        let kind: ResponseKind
        var quoted = offset
        switch bytes[offset] {
        case echoReply:
            kind = .echoReply
        case timeExceeded, destinationUnreachable:
            kind = bytes[offset] == timeExceeded ? .timeExceeded : .unreachable
            let inner = offset + headerSize
            guard bytes.count >= inner + 20, bytes[inner] >> 4 == 4, bytes[inner + 9] == UInt8(IPPROTO_ICMP)
            else { return nil }
            quoted = inner + Int(bytes[inner] & 0x0f) * 4
            guard bytes.count >= quoted + headerSize, bytes[quoted] == echoRequest else { return nil }
        default:
            return nil
        }
        let id = UInt16(bytes[quoted + 4]) << 8 | UInt16(bytes[quoted + 5])
        let seq = UInt16(bytes[quoted + 6]) << 8 | UInt16(bytes[quoted + 7])
        return (kind, id, seq)
    }
}
