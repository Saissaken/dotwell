import Foundation

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

    /// Default targets (see docs/REQUIREMENTS.md, open question Q1).
    public static let defaults: [PingTarget] = [
        PingTarget(name: "Router", host: gatewayHost, method: .icmp),
        PingTarget(name: "Cloudflare", host: "1.1.1.1", method: .icmp),
        PingTarget(name: "Google", host: "8.8.8.8", method: .icmp),
        PingTarget(name: "AWS São Paulo", host: "dynamodb.sa-east-1.amazonaws.com", method: .tcp(port: 443)),
        PingTarget(name: "AWS Virginia", host: "dynamodb.us-east-1.amazonaws.com", method: .tcp(port: 443)),
    ]
    /// Index of the target that drives the traffic light by default (Cloudflare).
    public static let defaultPrimaryIndex = 1

    /// The ping card has room for this many targets.
    public static let maximumCount = 8

    /// Ready-made targets offered in Settings, grouped by provider.
    public static let presets: [PingPresetGroup] = [
        PingPresetGroup(
            name: "Network",
            targets: [
                PingTarget(name: "Router", host: gatewayHost, method: .icmp),
                PingTarget(name: "Cloudflare", host: "1.1.1.1", method: .icmp),
                PingTarget(name: "Google", host: "8.8.8.8", method: .icmp),
                PingTarget(name: "Quad9", host: "9.9.9.9", method: .icmp),
            ]),
        PingPresetGroup(name: "Amazon Web Services", targets: awsRegions.map(aws)),
    ]

    /// An IPv4 address or a host name. The ping engine is IPv4-only, and URLs or spaces are a typo.
    public static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, host.first != ".", host.first != "-" else { return false }
        return host.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-")
        }
    }

    /// AWS regions by code and city. DynamoDB has a plain HTTPS endpoint in every region and AWS drops
    /// ICMP, so these are measured with a TCP handshake on port 443.
    static let awsRegions: [(code: String, city: String)] = [
        ("us-east-1", "Virginia"), ("us-east-2", "Ohio"), ("us-west-1", "California"), ("us-west-2", "Oregon"),
        ("ca-central-1", "Montréal"), ("sa-east-1", "São Paulo"), ("eu-west-1", "Ireland"),
        ("eu-west-2", "London"), ("eu-west-3", "Paris"), ("eu-central-1", "Frankfurt"),
        ("eu-north-1", "Stockholm"), ("ap-south-1", "Mumbai"), ("ap-southeast-1", "Singapore"),
        ("ap-southeast-2", "Sydney"), ("ap-northeast-1", "Tokyo"), ("ap-northeast-2", "Seoul"),
    ]

    private static func aws(_ region: (code: String, city: String)) -> PingTarget {
        PingTarget(name: "AWS \(region.city)", host: "dynamodb.\(region.code).amazonaws.com", method: .tcp(port: 443))
    }
}

/// A named list of preset targets, such as one cloud provider's regions.
public struct PingPresetGroup: Sendable {
    public var name: String
    public var targets: [PingTarget]
}
