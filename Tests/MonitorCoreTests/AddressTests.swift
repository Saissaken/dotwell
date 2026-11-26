import Darwin
import XCTest

@testable import MonitorCore

final class AddressTests: XCTestCase {
    private let trace = """
        fl=123f45
        h=1.1.1.1
        ip=203.0.113.24
        ts=1764131000.123
        visit_scheme=https
        """

    func testParsesIPv4FromTrace() {
        XCTAssertEqual(PublicAddressLookup.parse(trace, family: AF_INET), "203.0.113.24")
    }

    func testParsesIPv6FromTrace() {
        let body = "h=[2606:4700:4700::1111]\nip=2001:db8::1\nloc=AR\n"
        XCTAssertEqual(PublicAddressLookup.parse(body, family: AF_INET6), "2001:db8::1")
    }

    func testRejectsAddressOfTheWrongFamilyOrGarbage() {
        XCTAssertNil(PublicAddressLookup.parse(trace, family: AF_INET6))
        XCTAssertNil(PublicAddressLookup.parse("ip=<html>\n", family: AF_INET))
        XCTAssertNil(PublicAddressLookup.parse("no ip here", family: AF_INET))
    }

    func testLinkLocalIsSkipped() {
        var address = in_addr()
        inet_pton(AF_INET, "169.254.10.2", &address)
        XCTAssertTrue(LocalAddressReader.isLinkLocal(address))
        inet_pton(AF_INET, "192.168.1.42", &address)
        XCTAssertFalse(LocalAddressReader.isLinkLocal(address))
        XCTAssertEqual(LocalAddressReader.format(address), "192.168.1.42")
    }

    func testTunnelsAreVPN() {
        XCTAssertEqual(LocalAddressReader.kind(of: "utun4"), .vpn)
        XCTAssertEqual(LocalAddressReader.kind(of: "ipsec0"), .vpn)
    }

    func testReadsSomeLocalAddressWithoutCrashing() {
        // CI runners have a network; the exact address is not checked.
        if let local = LocalAddressReader.read() {
            XCTAssertFalse(local.ipv4.isEmpty)
            XCTAssertFalse(local.interface.isEmpty)
        }
    }
}
