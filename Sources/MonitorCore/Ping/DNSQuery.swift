/// Minimal DNS messages (RFC 1035) to time a resolver: one A query out, the header of the answer back.
enum DNSQuery {
    /// Popular enough to be in any resolver's cache, so the time is the resolver's, not a recursive lookup's.
    static let name = "www.apple.com"

    static func query(id: UInt16, name: String = DNSQuery.name) -> [UInt8] {
        var p: [UInt8] = [
            UInt8(id >> 8), UInt8(id & 0xff),
            0x01, 0x00,  // standard query, recursion desired
            0x00, 0x01,  // one question
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8.prefix(63))
            p.append(UInt8(bytes.count))
            p.append(contentsOf: bytes)
        }
        p.append(0)
        p.append(contentsOf: [0x00, 0x01, 0x00, 0x01])  // type A, class IN
        return p
    }

    /// The answer's id and whether the resolver answered the question (NOERROR or NXDOMAIN, not SERVFAIL or
    /// REFUSED), or nil if this is not a DNS response.
    static func parseResponse(_ bytes: UnsafeRawBufferPointer) -> (id: UInt16, ok: Bool)? {
        guard bytes.count >= 12, bytes[2] & 0x80 != 0 else { return nil }
        let id = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let rcode = bytes[3] & 0x0f
        return (id, rcode == 0 || rcode == 3)
    }
}
