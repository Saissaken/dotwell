import MonitorCore
import XCTest

@testable import MonitorUI

/// The words and figures of a ping row's detail.
final class PingDetailViewTests: XCTestCase {
    private func state(
        _ target: PingTarget, address: String?, minute: [Float] = [], interval: Int = 1
    ) -> PingTargetState {
        PingTargetState(
            index: 0, target: target, stats: PingStats.compute(minute), isPrimary: false, address: address,
            lastMinute: minute, probeIntervalSeconds: interval)
    }

    private func value(_ label: String, in lines: [PingDetail.Line]) -> String? {
        lines.first { $0.label == label }?.value
    }

    func testCloudRegionFacts() {
        let region = CloudRegion.defaultFirst
        let facts = PingDetail.facts(for: state(region.target, address: "198.51.100.18", interval: 5))
        XCTAssertEqual(value("Host", in: facts), "dynamodb.sa-east-1.amazonaws.com")
        XCTAssertEqual(value("Region", in: facts), "sa-east-1")
        XCTAssertEqual(value("IP", in: facts), "198.51.100.18")
        XCTAssertEqual(value("Measured", in: facts), "Time to open a connection (TCP port 443), every 5 seconds")
    }

    func testDiscoveredHostFacts() {
        let router = PingDetail.facts(for: state(.router, address: "192.168.1.1"))
        XCTAssertEqual(value("Host", in: router), "Your Wi-Fi or Ethernet router")
        XCTAssertEqual(value("Measured", in: router), "Ping (ICMP echo), every second")
        XCTAssertNil(value("Region", in: router))
        XCTAssertEqual(value("IP", in: PingDetail.facts(for: state(.isp, address: nil))), "Looking for it…")
        let dns = PingDetail.facts(for: state(.dns, address: "1.1.1.1", interval: 5))
        XCTAssertEqual(value("Measured", in: dns), "Time to answer a DNS query, every 5 seconds")
    }

    /// A literal address is not repeated as a host name.
    func testLiteralHostIsShownOnce() {
        let facts = PingDetail.facts(for: state(InternetHost.cloudflare.target, address: "1.1.1.1"))
        XCTAssertNil(value("Host", in: facts))
        XCTAssertEqual(value("IP", in: facts), "1.1.1.1")
    }

    func testFiguresComeFromTheLastMinute() {
        let figures = PingDetail.figures(PingStats.compute([10, 14, PingStats.lost, 12]))
        XCTAssertEqual(value("Average", in: figures), "12 ms")
        XCTAssertEqual(value("Min", in: figures), "10 ms")
        XCTAssertEqual(value("Max", in: figures), "14 ms")
        XCTAssertEqual(value("Loss", in: figures), "25 %")
        XCTAssertEqual(value("Jitter", in: figures), "3.0 ms")
        XCTAssertEqual(PingDetail.figures(PingStats.compute([])).map(\.value), ["—", "—", "—", "—", "—"])
        XCTAssertEqual(value("Loss", in: PingDetail.figures(PingStats.compute([PingStats.lost]))), "100 %")
    }

    func testWindowTitleSaysHowMuchIsCovered() {
        let full = state(.router, address: nil, minute: Array(repeating: 3, count: 60))
        XCTAssertEqual(PingDetail.windowTitle(full), "Last Minute")
        let young = state(.router, address: nil, minute: Array(repeating: 3, count: 4), interval: 5)
        XCTAssertEqual(PingDetail.windowTitle(young), "Last 20 Seconds")
        XCTAssertEqual(PingDetail.windowTitle(state(.router, address: nil)), "Last Minute")
    }
}
