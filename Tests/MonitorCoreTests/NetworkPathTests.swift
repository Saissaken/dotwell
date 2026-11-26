import Dispatch
import XCTest

@testable import MonitorCore

final class NetworkPathTests: XCTestCase {
    private func hop(
        _ ttl: Int, _ address: String?, _ hostname: String? = nil, ms: Float = 10, lost: Int = 0,
        destination: Bool = false
    ) -> TraceHop {
        let replies = Array(repeating: ms, count: 10 - lost)
        let samples = address == nil ? [] : replies + Array(repeating: PingStats.lost, count: lost)
        return TraceHop(
            ttl: ttl, address: address, hostname: hostname, stats: PingStats.compute(samples),
            isDestination: destination)
    }

    private var healthyHops: [TraceHop] {
        [
            hop(1, "192.168.1.1", ms: 3),
            hop(2, "100.64.0.1", ms: 8),
            hop(3, "200.51.240.17", "ae3.core1.andesnet.com.ar", ms: 9),
            hop(4, nil),
            hop(5, "181.30.1.5", "ae0.core2.andesnet.com.ar", ms: 10),
            hop(6, "195.22.220.57", "et-1-1.transit.example.net", ms: 12),
            hop(7, "1.1.1.1", "one.one.one.one", ms: 14, destination: true),
        ]
    }

    func testGroupsHopsIntoStages() {
        let path = NetworkPath(trace: PathTrace(hops: healthyHops, rounds: 10))
        XCTAssertEqual(path[.router].hops.map(\.ttl), [1])
        XCTAssertEqual(path[.isp].hops.map(\.ttl), [2, 3, 4, 5])
        XCTAssertEqual(path[.isp].name, "Andesnet")
        XCTAssertEqual(path[.internet].hops.map(\.ttl), [6])
        XCTAssertEqual(path[.server].hops.map(\.ttl), [7])
        XCTAssertEqual(path[.server].latencyMs, 14)
        XCTAssertEqual(path.verdict, .healthy)
        XCTAssertEqual(path.segments.map(\.level), [.ok, .ok, .ok, .ok, .ok])
    }

    func testLatencyStartingAtTheISP() {
        var hops = healthyHops
        hops[2] = hop(3, "200.51.240.17", "ae3.core1.andesnet.com.ar", ms: 90)
        hops[4] = hop(5, "181.30.1.5", "ae0.core2.andesnet.com.ar", ms: 95)
        hops[5] = hop(6, "195.22.220.57", ms: 98)
        hops[6] = hop(7, "1.1.1.1", ms: 110, destination: true)
        let path = NetworkPath(trace: PathTrace(hops: hops, rounds: 10))
        XCTAssertEqual(path[.router].level, .ok)
        XCTAssertEqual(path[.isp].level, .warning)
        XCTAssertEqual(path.verdict, .slow(.isp))
    }

    func testLossAtOneRouterOnlyIsIgnored() {
        var hops = healthyHops
        hops[5] = hop(6, "195.22.220.57", ms: 12, lost: 6)  // rate-limits replies, traffic passes fine
        let path = NetworkPath(trace: PathTrace(hops: hops, rounds: 10))
        XCTAssertEqual(path[.internet].level, .ok)
        XCTAssertEqual(path.verdict, .healthy)
    }

    func testLossFromTheRouterOn() {
        let hops = healthyHops.map {
            hop(
                $0.ttl, $0.address, $0.hostname, ms: $0.stats.averageMs ?? 0, lost: $0.isSilent ? 0 : 3,
                destination: $0.isDestination)
        }
        let path = NetworkPath(trace: PathTrace(hops: hops, rounds: 10))
        XCTAssertEqual(path[.router].level, .critical)
        XCTAssertEqual(path.verdict, .losing(.router))
    }

    func testDestinationThatNeverAnswers() {
        let hops = Array(healthyHops.prefix(3))
        let path = NetworkPath(trace: PathTrace(hops: hops, rounds: 5))
        XCTAssertEqual(path[.server].level, .critical)
        XCTAssertNil(path[.internet].level)
        XCTAssertEqual(path.verdict, .noReply)
    }

    /// A cloud host that drops ICMP: the routers on the way answer, the host doesn't, and its own TCP
    /// measurement stands in for it.
    func testServerMeasuredWithoutICMP() {
        let hops = Array(healthyHops.prefix(6))
        let stats = PingStats.compute([30, 32, 34, PingStats.lost])
        let path = NetworkPath(trace: PathTrace(hops: hops, rounds: 5), serverStats: stats)
        XCTAssertEqual(path[.server].latencyMs, 32)
        XCTAssertEqual(path[.server].lossFraction, 0.25)
        XCTAssertEqual(path[.server].level, .critical)  // 25 % loss
        XCTAssertEqual(path.verdict, .losing(.server))

        let healthy = NetworkPath(
            trace: PathTrace(hops: hops, rounds: 5), serverStats: PingStats.compute([30, 32, 34]))
        XCTAssertEqual(healthy[.server].level, .ok)
        XCTAssertEqual(healthy.verdict, .healthy)
    }

    func testServerMeasuredWithoutICMPButSilent() {
        let hops = Array(healthyHops.prefix(6))
        let stats = PingStats.compute([PingStats.lost, PingStats.lost])
        let path = NetworkPath(trace: PathTrace(hops: hops, rounds: 5), serverStats: stats)
        XCTAssertEqual(path.verdict, .noReply)
    }

    func testTraceThatReachesTheServerIgnoresItsOwnMeasurement() {
        let path = NetworkPath(
            trace: PathTrace(hops: healthyHops, rounds: 10), serverStats: PingStats.compute([90, 90]))
        XCTAssertEqual(path[.server].latencyMs, 14)
    }

    func testStillTracingWithServerMeasurement() {
        let path = NetworkPath(
            trace: PathTrace(hops: [], rounds: 1), serverStats: PingStats.compute([30]))
        XCTAssertEqual(path.verdict, .tracing)
    }

    func testTracingUntilThereIsData() {
        XCTAssertEqual(NetworkPath(trace: nil).verdict, .tracing)
        XCTAssertEqual(NetworkPath(trace: PathTrace(hops: [], rounds: 1)).verdict, .tracing)
        XCTAssertNil(NetworkPath(trace: PathTrace(hops: [], rounds: 1))[.server].level)
    }

    func testPrivateAddresses() {
        for address in ["10.0.0.1", "172.20.1.1", "192.168.0.1", "100.100.1.1", "169.254.3.4"] {
            XCTAssertTrue(NetworkPath.isPrivate(address), address)
        }
        for address in ["8.8.8.8", "172.32.0.1", "100.128.0.1", "1.1.1.1"] {
            XCTAssertFalse(NetworkPath.isPrivate(address), address)
        }
    }

    func testOrganizationFromHostname() {
        XCTAssertEqual(NetworkPath.organization("host-1.static.andesnet.com.ar")?.domain, "andesnet.com.ar")
        XCTAssertEqual(NetworkPath.organization("host-1.static.andesnet.com.ar")?.name, "Andesnet")
        XCTAssertEqual(NetworkPath.organization("ae1.cr2.att.net")?.name, "ATT")
        XCTAssertEqual(NetworkPath.organization("po-1.isp.co.uk")?.domain, "isp.co.uk")
        XCTAssertNil(NetworkPath.organization("1.2.3.4"))
        XCTAssertNil(NetworkPath.organization(nil))
    }

    func testISPHopIsTheFirstProviderRouter() {
        XCTAssertEqual(NetworkPath.ispHop(in: healthyHops, gateway: "192.168.1.1"), "100.64.0.1")
        let doubleNAT = [
            hop(1, "192.168.68.1"), hop(2, "192.168.1.1"), hop(3, nil), hop(4, "181.30.1.5"),
        ]
        XCTAssertEqual(NetworkPath.ispHop(in: doubleNAT, gateway: "192.168.68.1"), "181.30.1.5")
        let onlyDestination = [hop(1, "192.168.1.1"), hop(2, "1.1.1.1", destination: true)]
        XCTAssertNil(NetworkPath.ispHop(in: onlyDestination, gateway: "192.168.1.1"))
    }

    func testCarrierNAT() {
        XCTAssertTrue(NetworkPath.isCarrierNAT("100.64.0.1"))
        XCTAssertTrue(NetworkPath.isCarrierNAT("100.127.255.1"))
        XCTAssertFalse(NetworkPath.isCarrierNAT("100.128.0.1"))
        XCTAssertFalse(NetworkPath.isCarrierNAT("10.0.0.1"))
    }

    // MARK: - Packets

    func testParseTimeExceededQuotingOurProbe() {
        let probe = ICMPPacket.echoRequest(identifier: 0xbeef, sequence: 42)
        var bytes: [UInt8] = [0x45] + Array(repeating: 0, count: 19)  // outer IPv4 header
        bytes += [ICMPPacket.timeExceeded, 0, 0, 0, 0, 0, 0, 0]
        var inner: [UInt8] = [0x45] + Array(repeating: 0, count: 19)
        inner[9] = 1  // ICMP
        bytes += inner + probe.prefix(8)
        let r = bytes.withUnsafeBytes { ICMPPacket.parseResponse($0) }
        XCTAssertEqual(r?.kind, .timeExceeded)
        XCTAssertEqual(r?.identifier, 0xbeef)
        XCTAssertEqual(r?.sequence, 42)
    }

    func testParseResponseIgnoresOtherErrors() {
        var bytes: [UInt8] = [0x45] + Array(repeating: 0, count: 19)
        bytes += [ICMPPacket.timeExceeded, 0, 0, 0, 0, 0, 0, 0]
        var inner: [UInt8] = [0x45] + Array(repeating: 0, count: 19)
        inner[9] = 17  // UDP, someone else's traceroute
        bytes += inner + Array(repeating: 0, count: 8)
        XCTAssertNil(bytes.withUnsafeBytes { ICMPPacket.parseResponse($0) })
    }

    // MARK: - Live

    /// Loopback answers at the first hop, which proves setting the TTL works on an unprivileged socket.
    func testLiveLoopbackTrace() {
        let queue = DispatchQueue(label: "trace.test")
        let trace = Traceroute(queue: queue)
        queue.sync {
            trace.start(host: "127.0.0.1")
            trace.probeRound()
        }
        let done = expectation(description: "reply")
        queue.asyncAfter(deadline: .now() + 0.5) { done.fulfill() }
        wait(for: [done], timeout: 3)
        let result = queue.sync { trace.snapshot() }
        XCTAssertEqual(result?.hops.count, 1)
        XCTAssertEqual(result?.hops.first?.isDestination, true)
        XCTAssertEqual(result?.hops.first?.address, "127.0.0.1")
        queue.sync { trace.stop() }
    }

    /// Prints a real trace when the machine has internet access; CI runners often block ICMP, so it never fails.
    func testLiveInternetTrace() throws {
        let queue = DispatchQueue(label: "trace.internet")
        let trace = Traceroute(queue: queue)
        queue.sync { trace.start(host: "1.1.1.1") }
        for round in 0..<3 {
            queue.asyncAfter(deadline: .now() + Double(round)) { trace.probeRound() }
        }
        let done = expectation(description: "rounds")
        queue.asyncAfter(deadline: .now() + 3.5) { done.fulfill() }
        wait(for: [done], timeout: 6)
        let result = queue.sync { trace.snapshot() }
        queue.sync { trace.stop() }
        guard let result, result.hops.contains(where: { !$0.isSilent }) else {
            throw XCTSkip("No ICMP replies from the internet here")
        }
        for hop in result.hops {
            print("trace", hop.ttl, hop.address ?? "*", hop.hostname ?? "", hop.stats.averageMs ?? -1)
        }
    }

    /// Finds and pings the provider's first router when the machine has internet access; never fails on CI.
    func testLiveISPTarget() throws {
        let queue = DispatchQueue(label: "isp.test")
        let engine = PingEngine(targets: [.isp], queue: queue)
        var replies: [Float?] = []
        engine.onResult = { _, ms in replies.append(ms) }
        for second in 0..<5 {
            queue.asyncAfter(deadline: .now() + Double(second)) {
                engine.collect()
                engine.probe([0])
            }
        }
        let done = expectation(description: "probes")
        queue.asyncAfter(deadline: .now() + 5.5) { done.fulfill() }
        wait(for: [done], timeout: 8)
        let results = queue.sync {
            engine.collect()
            return replies.compactMap { $0 }
        }
        guard !results.isEmpty else { throw XCTSkip("No provider router found here") }
        print("isp", results)
    }
}
