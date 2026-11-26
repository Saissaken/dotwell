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
    func testLiveLoopback() {
        let queue = DispatchQueue(label: "ping.test")
        let engine = PingEngine(
            targets: [
                PingTarget(name: "lo", host: "127.0.0.1", method: .icmp),
                PingTarget(name: "lo-tcp", host: "127.0.0.1", method: .tcp(port: 9)),
            ], queue: queue)
        let got = expectation(description: "results")
        got.expectedFulfillmentCount = 2
        var results: [Int: Float?] = [:]
        engine.onResult = { i, ms in
            results[i] = ms; got.fulfill()
        }
        queue.async { engine.probe([0, 1]) }
        wait(for: [got], timeout: 3)
        queue.sync {
            XCTAssertNotNil(results[0] ?? nil, "ICMP to loopback should reply")
            XCTAssertNotNil(results[1] ?? nil, "TCP refused should count as a round trip")
        }
    }
}
