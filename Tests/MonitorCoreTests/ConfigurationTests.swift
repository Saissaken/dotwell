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

    func testHostValidation() {
        for host in ["1.1.1.1", "example.com", "dynamodb.sa-east-1.amazonaws.com", "router"] {
            XCTAssertTrue(PingTarget.isValidHost(host), host)
        }
        for host in ["", "https://example.com", "exa mple.com", ".com", "-a", "::1", "ejemplo.ñ"] {
            XCTAssertFalse(PingTarget.isValidHost(host), host)
        }
    }

    func testPresetsAreValidAndUnique() {
        let targets = PingTarget.presets.flatMap(\.targets)
        XCTAssertEqual(Set(targets).count, targets.count)
        for target in targets where !target.isGateway { XCTAssertTrue(PingTarget.isValidHost(target.host)) }
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
