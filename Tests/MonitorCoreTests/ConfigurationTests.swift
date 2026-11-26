import XCTest

@testable import MonitorCore

final class ConfigurationTests: XCTestCase {
    func testHistoryRangesAdaptToTheInterval() {
        var s = TieredSeries()
        for i in 0..<60 { s.append(Float(i)) }
        XCTAssertEqual(s.values(for: .seconds30).count, 30)
        XCTAssertEqual(s.values(for: .seconds30, interval: 2).count, 15)
        XCTAssertEqual(s.values(for: .seconds30, interval: 10), [57, 58, 59])
        XCTAssertEqual(s.values(for: .minutes5, interval: 5).count, 12)
    }

    func testThresholdsDecodeWithMissingKeys() throws {
        let data = Data(#"{"pingWarningMs": 42}"#.utf8)
        let thresholds = try JSONDecoder().decode(Thresholds.self, from: data)
        var expected = Thresholds()
        expected.pingWarningMs = 42
        XCTAssertEqual(thresholds, expected)
    }

    func testPingTargetsRoundTrip() throws {
        let data = try JSONEncoder().encode(PingTarget.defaults)
        XCTAssertEqual(try JSONDecoder().decode([PingTarget].self, from: data), PingTarget.defaults)
    }

    func testRegionCatalog() {
        let ids = CloudRegion.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(CloudRegion.all.map(\.host)).count, ids.count)
        for provider in CloudProvider.allCases { XCTAssertFalse(CloudRegion.regions(of: provider).isEmpty) }
        XCTAssertEqual(CloudRegion.find(.aws, "sa-east-1"), CloudRegion.defaultFirst)
        XCTAssertEqual(CloudRegion.defaultSecond.target.host, "dynamodb.us-east-1.amazonaws.com")
        XCTAssertNil(CloudRegion.find(.azure, "nowhere"))
        XCTAssertEqual(CloudRegion.find(.gcp, "us-east4")?.target.method, .https(path: "/storage/v1/b/_"))
    }

    func testDefaultTargets() {
        XCTAssertEqual(
            PingTarget.defaults.map(\.name),
            ["Router", "ISP", "DNS", "Cloudflare", "AWS São Paulo", "AWS Virginia"])
        XCTAssertEqual(PingTarget.defaults[PingTarget.defaultPrimaryIndex].host, "1.1.1.1")
        XCTAssertTrue(PingTarget.defaults[1].isISP)
        XCTAssertTrue(PingTarget.defaults[2].isDNS)
    }

    func testDNSRowName() {
        func name(_ address: String?, router: String? = "192.168.1.1") -> String {
            PingTargetState(index: 0, target: .dns, stats: PingStats.compute([]), isPrimary: false, address: address)
                .displayName(routerAddress: router)
        }
        XCTAssertEqual(name(nil), "DNS")
        XCTAssertEqual(name("1.1.1.1"), "DNS Cloudflare")
        XCTAssertEqual(name("8.8.4.4"), "DNS Google")
        XCTAssertEqual(name("192.168.1.1"), "DNS Router")
        XCTAssertEqual(name("200.45.191.35"), "DNS 200.45.191.35")
        let router = PingTargetState(
            index: 0, target: .router, stats: PingStats.compute([]), isPrimary: false, address: "192.168.1.1")
        XCTAssertEqual(router.displayName(routerAddress: "192.168.1.1"), "Router")
    }

    func testFirstIPv4DNSServer() {
        XCTAssertNil(DNSServer.firstIPv4(["2606:4700:4700::1111"]))
        let found = DNSServer.firstIPv4(["fe80::1", "192.168.1.1", "8.8.8.8"]).map(Traceroute.text)
        XCTAssertEqual(found, "192.168.1.1")
    }

    func testPrimaryIsClampedToActiveTargets() {
        var config = SamplerConfiguration(primaryIndex: 9)
        XCTAssertEqual(config.activePrimaryIndex, PingTarget.defaults.count - 1)
        config.pingEnabled = false
        XCTAssertTrue(config.activeTargets.isEmpty)
        XCTAssertEqual(config.activePrimaryIndex, 0)
    }

    func testSamplerAppliesNewTargetsAndAlerts() {
        let sampler = Sampler(targets: [PingTarget(name: "lo", host: "127.0.0.1", method: .icmp)])
        let got = expectation(description: "reconfigured")
        got.assertForOverFulfill = false
        sampler.onSnapshot = { snap in
            if snap.ping.map(\.target.name) == ["a", "b"], snap.primaryPing?.target.name == "b",
                snap.levels[.cpu] == nil, snap.thresholds.cpuWarning == 0.5
            {
                got.fulfill()
            }
        }
        var config = SamplerConfiguration(
            targets: [
                PingTarget(name: "a", host: "127.0.0.1", method: .icmp),
                PingTarget(name: "b", host: "127.0.0.1", method: .tcp(port: 9)),
            ], primaryIndex: 1)
        config.alerts.remove(.cpu)
        config.thresholds.cpuWarning = 0.5
        sampler.start()
        sampler.apply(config)
        wait(for: [got], timeout: 5)
        sampler.stop()
    }
}
