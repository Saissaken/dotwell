import XCTest

@testable import MonitorCore

final class PingTests: XCTestCase {
    func testChecksumOfRequestIsValid() {
        let p = ICMPPacket.echoRequest(identifier: 0x1234, sequence: 7)
        XCTAssertEqual(ICMPPacket.checksum(p), 0)  // checksum over a packet with its checksum folds to 0
    }

    func testParseReplyWithIPHeader() {
        var bytes = [UInt8](repeating: 0, count: 20 + 16)
        bytes[0] = 0x45  // IPv4, IHL 5
        bytes[20] = ICMPPacket.echoReply
        bytes[24] = 0x12; bytes[25] = 0x34; bytes[26] = 0x00; bytes[27] = 0x07
        let r = bytes.withUnsafeBytes { ICMPPacket.parseEchoReply($0) }
        XCTAssertEqual(r?.identifier, 0x1234)
        XCTAssertEqual(r?.sequence, 7)
    }

    func testParseRejectsRequest() {
        let p = ICMPPacket.echoRequest(identifier: 1, sequence: 1)
        XCTAssertNil(p.withUnsafeBytes { ICMPPacket.parseEchoReply($0) })
    }

    func testStats() {
        let s = PingStats.compute([10, 20, PingStats.lost, 30])
        XCTAssertEqual(s.latestMs, 30)
        XCTAssertEqual(s.averageMs, 20)
        XCTAssertEqual(s.maxMs, 30)
        XCTAssertEqual(s.lossFraction, 0.25)
        XCTAssertEqual(s.jitterMs, 10)
        XCTAssertFalse(s.lastLost)
    }

    func testStatsMinimumSkipsLostReplies() {
        let s = PingStats.compute([12, PingStats.lost, 7.5, 40])
        XCTAssertEqual(s.minMs, 7.5)
        XCTAssertEqual(s.maxMs, 40)
        XCTAssertNil(PingStats.compute([PingStats.lost]).minMs)
        XCTAssertNil(PingStats.compute([]).minMs)
    }

    func testStatsAllLost() {
        let s = PingStats.compute([PingStats.lost, PingStats.lost])
        XCTAssertNil(s.latestMs)
        XCTAssertEqual(s.lossFraction, 1)
        XCTAssertTrue(s.lastLost)
    }

    func testGatewayLookupDoesNotCrash() {
        _ = Gateway.defaultIPv4()
    }

    /// Live: localhost answers ICMP and refuses TCP on an unused port, both within the timeout.
    /// The ICMP reply is only read by the next `collect()`, but its round trip is the kernel's.
    func testLiveLoopback() {
        let queue = DispatchQueue(label: "ping.test")
        let engine = PingEngine(
            targets: [
                PingTarget(name: "lo", host: "127.0.0.1", method: .icmp),
                PingTarget(name: "lo-tcp", host: "127.0.0.1", method: .tcp(port: 9)),
            ], queue: queue)
        var results: [Int: Float?] = [:]
        engine.onResult = { i, ms in results[i] = ms }
        queue.sync { engine.probe([0, 1]) }
        let waited = expectation(description: "replies arrive")
        queue.asyncAfter(deadline: .now() + 0.5) { waited.fulfill() }
        wait(for: [waited], timeout: 3)
        queue.sync {
            XCTAssertNil(results[0], "ICMP replies wait for collect()")
            XCTAssertNotNil(results[1] ?? nil, "TCP refused should count as a round trip")
            engine.collect()
            let ms = results[0] ?? nil
            XCTAssertNotNil(ms, "ICMP to loopback should reply")
            // Read half a second later, yet timed when it arrived.
            XCTAssertLessThan(ms ?? .infinity, 50)
        }
    }

    /// Probes unanswered for the timeout count as lost; younger ones stay pending, so a 0.5 s tick doesn't
    /// shorten the timeout.
    func testCollectReportsUnansweredAsLostAfterTheTimeout() {
        let queue = DispatchQueue(label: "ping.lost")
        // TEST-NET-1 (RFC 5737) is never routed, so nothing answers.
        let engine = PingEngine(targets: [PingTarget(name: "void", host: "192.0.2.1", method: .icmp)], queue: queue)
        engine.timeoutNanos = 200_000_000
        var results: [Float?] = []
        engine.onResult = { _, ms in results.append(ms) }
        queue.sync {
            engine.probe([0])
            engine.collect()
            XCTAssertEqual(results, [], "still within the timeout")
        }
        let waited = expectation(description: "timeout passes")
        queue.asyncAfter(deadline: .now() + 0.3) { waited.fulfill() }
        wait(for: [waited], timeout: 3)
        queue.sync {
            engine.collect()
            XCTAssertEqual(results, [nil])
            engine.collect()
            XCTAssertEqual(results, [nil], "reported once")
        }
    }

    /// The kernel timestamps ICMP replies, so the app's own delays never count as latency.
    func testLiveKernelTimestamp() throws {
        let fd = ICMPSocket.open()
        try XCTSkipIf(fd < 0, "No ICMP socket here")
        defer { close(fd) }
        let packet = ICMPPacket.echoRequest(identifier: 0x4242, sequence: 1)
        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_family = sa_family_t(AF_INET)
        sa.sin_addr.s_addr = inet_addr("127.0.0.1")
        let sentAt = ICMPSocket.now()
        _ = packet.withUnsafeBytes { buf in
            withUnsafePointer(to: &sa) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        usleep(200_000)
        var buffer = [UInt8](repeating: 0, count: 256)
        var reply: ICMPSocket.Packet?
        while let next = ICMPSocket.receive(fd, into: &buffer) {
            let parsed = buffer.withUnsafeBytes {
                ICMPPacket.parseEchoReply(UnsafeRawBufferPointer(rebasing: $0[0..<next.length]))
            }
            if parsed?.identifier == 0x4242 { reply = next }
        }
        let got = try XCTUnwrap(reply, "loopback should reply")
        XCTAssertTrue(got.kernelTimestamp)
        XCTAssertGreaterThanOrEqual(got.receivedAt, sentAt)
        XCTAssertLessThan(got.receivedAt - sentAt, 50_000_000, "stamped on arrival, not when read 200 ms later")
    }

    func testFindsTimestampAmongControlMessages() {
        // An unrelated 16-byte message, then the 20-byte timestamp message.
        var bytes = [UInt8](repeating: 0, count: 36)
        func put(_ value: UInt32, at offset: Int) {
            withUnsafeBytes(of: value) { bytes.replaceSubrange(offset..<offset + 4, with: $0) }
        }
        put(16, at: 0)
        put(UInt32(IPPROTO_IP), at: 4)
        put(1, at: 8)
        put(20, at: 16)
        put(UInt32(SOL_SOCKET), at: 20)
        put(4, at: 24)
        withUnsafeBytes(of: UInt64(123_456_789)) { bytes.replaceSubrange(28..<36, with: $0) }
        let found = bytes.withUnsafeBytes { ICMPSocket.timestamp(in: $0, length: bytes.count) }
        XCTAssertEqual(found, 123_456_789)
        let missing = bytes.withUnsafeBytes { ICMPSocket.timestamp(in: $0, length: 16) }
        XCTAssertNil(missing)
    }
}
