/// A host we measure latency against.
public struct PingTarget: Hashable, Sendable, Codable {
    public enum Method: Hashable, Sendable, Codable {
        /// ICMP echo via an unprivileged datagram socket.
        case icmp
        /// Time to complete a TCP handshake. Used for hosts that drop ICMP (e.g. AWS endpoints).
        case tcp(port: UInt16)
    }

    /// Special host value meaning "the current default IPv4 gateway (your router)".
    public static let gatewayHost = "@gateway"

    public var name: String
    public var host: String
    public var method: Method

    public init(name: String, host: String, method: Method) {
        self.name = name; self.host = host; self.method = method
    }

    public var isGateway: Bool { host == Self.gatewayHost }

    /// Defaults (see docs/REQUIREMENTS.md, open question Q1). The first entry with
    /// `isPrimary` semantics is index 1 (Cloudflare) until the user picks one.
    public static let defaults: [PingTarget] = [
        PingTarget(name: "Router", host: gatewayHost, method: .icmp),
        PingTarget(name: "Cloudflare", host: "1.1.1.1", method: .icmp),
        PingTarget(name: "Google", host: "8.8.8.8", method: .icmp),
        PingTarget(name: "AWS São Paulo", host: "dynamodb.sa-east-1.amazonaws.com", method: .tcp(port: 443)),
        PingTarget(name: "AWS Virginia", host: "dynamodb.us-east-1.amazonaws.com", method: .tcp(port: 443)),
    ]
    public static let defaultPrimaryIndex = 1
}
