/// A host we measure latency against.
public struct PingTarget: Hashable, Sendable, Codable {
    public enum Method: Hashable, Sendable, Codable {
        /// ICMP echo via an unprivileged datagram socket.
        case icmp
        /// Time to complete a TCP handshake. Used for hosts that drop ICMP (e.g. AWS endpoints).
        case tcp(port: UInt16)
        /// Time from sending a small HTTPS GET to the first byte of the answer, on a kept-alive
        /// connection. For hosts behind an anycast edge, where the handshake would only reach the edge.
        case https(path: String)
    }

    /// Special host value meaning "the current default IPv4 gateway (your router)".
    public static let gatewayHost = "@gateway"
    /// Special host value meaning "the first router of your internet provider", past your own router.
    public static let ispHost = "@isp"
    /// Special host value meaning "the DNS server macOS is set to use".
    public static let dnsHost = "@dns"

    public var name: String
    public var host: String
    public var method: Method

    public init(name: String, host: String, method: Method) {
        self.name = name; self.host = host; self.method = method
    }

    public var isGateway: Bool { host == Self.gatewayHost }
    public var isISP: Bool { host == Self.ispHost }
    public var isDNS: Bool { host == Self.dnsHost }
    /// Router, ISP and DNS: found on the Mac's current network rather than named by a host.
    public var isDiscovered: Bool { isGateway || isISP || isDNS }

    public static let router = PingTarget(name: "Router", host: gatewayHost, method: .icmp)
    public static let isp = PingTarget(name: "ISP", host: ispHost, method: .icmp)
    public static let dns = PingTarget(name: "DNS", host: dnsHost, method: .icmp)

    /// Default targets: your network (router, ISP, DNS server), the internet (Cloudflare) and two cloud regions.
    public static let defaults: [PingTarget] = [
        router, isp, dns, InternetHost.cloudflare.target,
        CloudRegion.defaultFirst.target, CloudRegion.defaultSecond.target,
    ]
    /// Index of the target that drives the traffic light by default (Cloudflare).
    public static let defaultPrimaryIndex = 3
}

/// Public anycast hosts that stand for "the internet": the nearest of their servers answers.
public enum InternetHost: String, CaseIterable, Codable, Sendable {
    case cloudflare, google, quad9

    public var target: PingTarget {
        switch self {
        case .cloudflare: return PingTarget(name: "Cloudflare", host: "1.1.1.1", method: .icmp)
        case .google: return PingTarget(name: "Google", host: "8.8.8.8", method: .icmp)
        case .quad9: return PingTarget(name: "Quad9", host: "9.9.9.9", method: .icmp)
        }
    }
}

public enum CloudProvider: String, CaseIterable, Codable, Sendable {
    case aws, gcp, azure

    public var title: String {
        switch self {
        case .aws: return "AWS"
        case .gcp: return "GCP"
        case .azure: return "Azure"
        }
    }
}

/// A cloud region and the endpoint that measures it. Cloud providers drop ICMP, so AWS and Azure are timed
/// with a TCP handshake on port 443 to an endpoint inside the region. Google Cloud terminates connections
/// at the nearest edge, so its regions are timed with a small HTTPS request answered by the region.
public struct CloudRegion: Hashable, Codable, Sendable, Identifiable {
    public var provider: CloudProvider
    /// The provider's region code, e.g. "sa-east-1" or "brazilsouth".
    public var code: String
    /// Short place name shown in the popover, e.g. "São Paulo".
    public var city: String
    public var host: String

    public var id: String { "\(provider.rawValue):\(code)" }

    public var target: PingTarget {
        let method: PingTarget.Method = provider == .gcp ? .https(path: "/storage/v1/b/_") : .tcp(port: 443)
        return PingTarget(name: "\(provider.title) \(city)", host: host, method: method)
    }

    public static let defaultFirst = aws("sa-east-1", "São Paulo")
    public static let defaultSecond = aws("us-east-1", "Virginia")

    public static func regions(of provider: CloudProvider) -> [CloudRegion] {
        all.filter { $0.provider == provider }
    }

    /// The catalog entry with this provider and code, so saved settings pick up endpoint changes.
    public static func find(_ provider: CloudProvider, _ code: String) -> CloudRegion? {
        all.first { $0.provider == provider && $0.code == code }
    }

    /// DynamoDB has a plain HTTPS endpoint in every AWS region.
    private static func aws(_ code: String, _ city: String) -> CloudRegion {
        CloudRegion(provider: .aws, code: code, city: city, host: "dynamodb.\(code).amazonaws.com")
    }

    /// Cloud Storage's regional endpoints answer from inside their region. The request names no real
    /// bucket, so it gets a tiny error response without touching anyone's data.
    private static func gcp(_ code: String, _ city: String) -> CloudRegion {
        CloudRegion(provider: .gcp, code: code, city: city, host: "storage.\(code).rep.googleapis.com")
    }

    /// Azure has no public per-region endpoint of its own, so these are the storage accounts that the
    /// open-source Azure Speed Test (github.com/richorama/AzureSpeedTest2) keeps in each region.
    private static func azure(_ code: String, _ city: String, _ host: String) -> CloudRegion {
        CloudRegion(provider: .azure, code: code, city: city, host: "\(host).web.core.windows.net")
    }

    public static let all: [CloudRegion] = [
        aws("us-east-1", "Virginia"), aws("us-east-2", "Ohio"), aws("us-west-1", "California"),
        aws("us-west-2", "Oregon"), aws("ca-central-1", "Montréal"), aws("mx-central-1", "Mexico"),
        aws("sa-east-1", "São Paulo"), aws("eu-west-1", "Ireland"), aws("eu-west-2", "London"),
        aws("eu-west-3", "Paris"), aws("eu-central-1", "Frankfurt"), aws("eu-south-2", "Spain"),
        aws("eu-north-1", "Stockholm"), aws("ap-south-1", "Mumbai"), aws("ap-southeast-1", "Singapore"),
        aws("ap-southeast-2", "Sydney"), aws("ap-northeast-1", "Tokyo"), aws("ap-northeast-2", "Seoul"),
        gcp("us-east4", "Virginia"), gcp("us-east1", "South Carolina"), gcp("us-central1", "Iowa"),
        gcp("us-south1", "Dallas"), gcp("us-west1", "Oregon"), gcp("us-west2", "Los Angeles"),
        gcp("northamerica-northeast1", "Montréal"), gcp("northamerica-south1", "Querétaro"),
        gcp("southamerica-east1", "São Paulo"), gcp("southamerica-west1", "Santiago"),
        gcp("europe-west1", "Belgium"), gcp("europe-west2", "London"), gcp("europe-west3", "Frankfurt"),
        gcp("europe-west4", "Netherlands"), gcp("europe-west9", "Paris"), gcp("europe-southwest1", "Madrid"),
        gcp("europe-north1", "Finland"), gcp("asia-south1", "Mumbai"), gcp("asia-southeast1", "Singapore"),
        gcp("asia-east1", "Taiwan"), gcp("asia-northeast1", "Tokyo"), gcp("asia-northeast3", "Seoul"),
        gcp("australia-southeast1", "Sydney"),
        azure("eastus", "Virginia", "steus09377.z13"),
        azure("centralus", "Iowa", "stcus09377.z19"),
        azure("southcentralus", "Texas", "speedtestscus18632.z21"),
        azure("westus2", "Washington", "speedtestwestus218632.z5"),
        azure("canadacentral", "Toronto", "speedtestcac18632.z9"),
        azure("mexicocentral", "Querétaro", "speedtestmmc18632.z41"),
        azure("brazilsouth", "São Paulo", "speedtestnea18632.z15"),
        azure("chilecentral", "Santiago", "speedtestchile53201.z47"),
        azure("northeurope", "Ireland", "speedtestne18632.z16"),
        azure("westeurope", "Netherlands", "speedtestwe07148.z6"),
        azure("uksouth", "London", "speedtestuks18632.z33"),
        azure("francecentral", "Paris", "speedtestfrc18632.z28"),
        azure("germanywestcentral", "Frankfurt", "speedtestden18632.z1"),
        azure("spaincentral", "Madrid", "speedtestspain53288.z43"),
        azure("centralindia", "Pune", "stci08318.z29"),
        azure("southeastasia", "Singapore", "speedtestsea18632.z23"),
        azure("japaneast", "Tokyo", "stjpe09377.z11"),
        azure("koreacentral", "Seoul", "stkc09377.z12"),
        azure("australiaeast", "Sydney", "speedtestoze18632.z8"),
    ]
}
