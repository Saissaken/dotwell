import Darwin
import Foundation

/// The addresses the internet sees for this Mac. Either family is `nil` when it has no route there.
public struct PublicAddresses: Sendable, Equatable {
    public var ipv4: String?
    public var ipv6: String?

    public init(ipv4: String? = nil, ipv6: String? = nil) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
    }

    public var isEmpty: Bool { ipv4 == nil && ipv6 == nil }
}

/// Asks Cloudflare's resolver which address a request came from (`/cdn-cgi/trace`). Connecting to the
/// resolver's literal IPv4 and IPv6 addresses forces each family, needs no DNS lookup, and the reply is
/// a few hundred bytes. No cookies, cache or identifiers are sent.
enum PublicAddressLookup {
    static let ipv4URL = URL(string: "https://1.1.1.1/cdn-cgi/trace")
    static let ipv6URL = URL(string: "https://[2606:4700:4700::1111]/cdn-cgi/trace")

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    static func fetch(using session: URLSession) async -> PublicAddresses {
        async let v4 = address(from: ipv4URL, family: AF_INET, session: session)
        async let v6 = address(from: ipv6URL, family: AF_INET6, session: session)
        return await PublicAddresses(ipv4: v4, ipv6: v6)
    }

    private static func address(from url: URL?, family: Int32, session: URLSession) async -> String? {
        guard let url, let reply = try? await session.data(from: url),
            (reply.1 as? HTTPURLResponse)?.statusCode == 200,
            let body = String(data: reply.0, encoding: .utf8)
        else { return nil }
        return parse(body, family: family)
    }

    /// Extracts the `ip=` line from a trace reply, accepting it only if it is a valid address of `family`.
    static func parse(_ body: String, family: Int32) -> String? {
        for line in body.split(whereSeparator: \.isNewline) where line.hasPrefix("ip=") {
            let value = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var storage = in6_addr()
            guard inet_pton(family, value, &storage) == 1 else { return nil }
            return value
        }
        return nil
    }
}
