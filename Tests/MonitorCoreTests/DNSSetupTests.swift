import XCTest

@testable import MonitorCore

/// How the DNS row's detail explains the Mac's DNS setup, from the values `configd` holds.
final class DNSSetupTests: XCTestCase {
    private let wifi = "8A2C0F7E-1111-4D5E-9F00-AAAAAAAAAAAA"
    private let vpn = "B3D1E2F4-2222-4C6A-8B11-BBBBBBBBBBBB"

    /// Tailscale's MagicDNS on top of a home router, as `configd` stores it: Tailscale's network extension
    /// has no Setup entry, and its tailnet domains go to it alone.
    private var tailscaleOverRouter: [String: Any] {
        [
            "State:/Network/Global/DNS": ["ServerAddresses": ["100.100.100.100"]],
            "State:/Network/Service/\(wifi)/DNS": [
                "ServerAddresses": ["192.168.1.1"], "SearchDomains": ["localdomain"],
            ],
            "State:/Network/Service/\(wifi)/IPv4": ["InterfaceName": "en0"],
            "Setup:/Network/Service/\(wifi)": ["UserDefinedName": "Wi-Fi"],
            "Setup:/Network/Service/\(wifi)/Interface": ["DeviceName": "en0", "UserDefinedName": "Wi-Fi"],
            "State:/Network/Service/\(vpn)/DNS": [
                "ServerAddresses": ["100.100.100.100"],
                "SupplementalMatchDomains": ["", "tail1234.ts.net", "100.100.in-addr.arpa"],
            ],
            "State:/Network/Service/\(vpn)/IPv4": ["InterfaceName": "utun4"],
        ]
    }

    private func value(_ label: String, in chain: DNSChain) -> String? {
        chain.lines.first { $0.label == label }?.value
    }

    func testParsesEveryResolver() {
        let setup = DNSSetup.parse(tailscaleOverRouter)
        XCTAssertEqual(setup.servers, ["100.100.100.100"])
        let wifi = setup.resolvers.first { $0.interface == "en0" }
        XCTAssertEqual(wifi?.source, "Wi-Fi")
        XCTAssertEqual(wifi?.servers, ["192.168.1.1"])
        XCTAssertEqual(wifi?.isVPN, false)
        XCTAssertEqual(wifi?.isManual, false)
        let tailscale = setup.resolvers.first { $0.interface == "utun4" }
        XCTAssertNil(tailscale?.source)
        XCTAssertEqual(tailscale?.isVPN, true)
        // The empty domain (answer everything) is not a domain of its own.
        XCTAssertEqual(tailscale?.matchDomains, ["tail1234.ts.net", "100.100.in-addr.arpa"])
    }

    /// The person's case: the row measures Tailscale, and the detail says who set it and what the network's
    /// own server is.
    func testTailscaleOverRouter() {
        let chain = DNSChain(
            setup: DNSSetup.parse(tailscaleOverRouter), answering: "100.100.100.100", routerAddress: "192.168.1.1")
        XCTAssertEqual(value("Set by", in: chain), "Tailscale (VPN)")
        XCTAssertEqual(value("Network", in: chain), "Router (192.168.1.1)")
        // Reverse-lookup domains are plumbing, not worth a line.
        XCTAssertEqual(value("Domains", in: chain), "tail1234.ts.net → Tailscale")
        XCTAssertNil(value("Backup", in: chain))
        XCTAssertEqual(
            chain.summary,
            "Tailscale is handling your Mac's DNS. It answers names on your tailnet and passes the rest on, "
                + "usually to your network's DNS.")
    }

    /// Servers typed in System Settings win over the ones the network hands out, as they do for macOS.
    func testServersSetByHand() {
        var values = tailscaleOverRouter
        values["State:/Network/Global/DNS"] = ["ServerAddresses": ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111"]]
        values["Setup:/Network/Service/\(wifi)/DNS"] = ["ServerAddresses": ["1.1.1.1", "1.0.0.1"]]
        values["State:/Network/Service/\(vpn)/DNS"] = nil
        let setup = DNSSetup.parse(values)
        XCTAssertEqual(setup.resolvers.count, 1)
        XCTAssertEqual(setup.resolvers.first?.servers, ["1.1.1.1", "1.0.0.1"])
        let chain = DNSChain(setup: setup, answering: "1.1.1.1", routerAddress: "192.168.1.1")
        XCTAssertEqual(value("Set by", in: chain), "Wi-Fi (set by hand)")
        XCTAssertEqual(value("Backup", in: chain), "Cloudflare (1.0.0.1)")
        XCTAssertNil(value("Network", in: chain))
        // A single server in play needs no explanation.
        XCTAssertNil(chain.summary)
    }

    /// The plain home case: the router answers, handed out by the network, nothing else in play.
    func testRouterOnly() {
        var values = tailscaleOverRouter
        values["State:/Network/Global/DNS"] = ["ServerAddresses": ["192.168.1.1"]]
        values["State:/Network/Service/\(vpn)/DNS"] = nil
        let chain = DNSChain(
            setup: DNSSetup.parse(values), answering: "192.168.1.1", routerAddress: "192.168.1.1")
        XCTAssertEqual(chain.lines.map(\.label), ["Set by"])
        XCTAssertEqual(value("Set by", in: chain), "Wi-Fi (from the network)")
        XCTAssertNil(chain.summary)
    }

    /// A company VPN that only answers its own domains: everything else still goes to the router.
    func testSplitVPN() {
        var values = tailscaleOverRouter
        values["State:/Network/Global/DNS"] = ["ServerAddresses": ["192.168.1.1"]]
        values["State:/Network/Service/\(vpn)/DNS"] = [
            "ServerAddresses": ["10.0.0.53"], "SupplementalMatchDomains": ["corp.example.com", "example.net", "x.io"],
        ]
        values["Setup:/Network/Service/\(vpn)"] = ["UserDefinedName": "Work VPN"]
        let chain = DNSChain(
            setup: DNSSetup.parse(values), answering: "192.168.1.1", routerAddress: "192.168.1.1")
        XCTAssertEqual(value("Set by", in: chain), "Wi-Fi (from the network)")
        XCTAssertEqual(value("Domains", in: chain), "corp.example.com, example.net +1 → Work VPN")
        XCTAssertEqual(chain.summary, "Lookups go to Router (192.168.1.1). The domains listed go to their own server.")
    }

    /// A filtering app answering on this Mac, with no network service behind it.
    func testLocalResolver() {
        var values = tailscaleOverRouter
        values["State:/Network/Global/DNS"] = ["ServerAddresses": ["127.0.0.1"]]
        values["State:/Network/Service/\(vpn)/DNS"] = nil
        let chain = DNSChain(setup: DNSSetup.parse(values), answering: "127.0.0.1", routerAddress: "192.168.1.1")
        XCTAssertNil(value("Set by", in: chain))
        XCTAssertEqual(value("Network", in: chain), "Router (192.168.1.1)")
        XCTAssertEqual(chain.summary, "An app on this Mac is handling its DNS, instead of your network's server.")
    }

    func testNames() {
        XCTAssertEqual(DNSServer.label(of: "8.8.8.8", routerAddress: nil), "Google (8.8.8.8)")
        XCTAssertEqual(DNSServer.label(of: "10.1.2.3", routerAddress: nil), "10.1.2.3")
        XCTAssertEqual(DNSServer.name(of: "76.76.2.11", routerAddress: nil), "Control D")
        XCTAssertNil(DNSServer.name(of: "45.90.29.1", routerAddress: nil))
    }

    /// A change is the address moving between two known values: losing the network is not one.
    func testChangeTracker() {
        var tracker = DNSChangeTracker()
        let start = Date(timeIntervalSince1970: 1000)
        tracker.observe("192.168.1.1", now: start)
        XCTAssertNil(tracker.change, "The first address seen is not a change")
        tracker.observe("192.168.1.1", now: start + 30)
        tracker.observe(nil, now: start + 60)
        tracker.observe("192.168.1.1", now: start + 90)
        XCTAssertNil(tracker.change)
        tracker.observe("100.100.100.100", now: start + 120)
        XCTAssertEqual(tracker.change, DNSChange(previous: "192.168.1.1", at: start + 120))
        tracker.observe("100.100.100.100", now: start + 150)
        XCTAssertEqual(tracker.change?.at, start + 120, "Kept until the next change")
    }
}
