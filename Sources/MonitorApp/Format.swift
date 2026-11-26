import Foundation

enum Format {
    static func percent(_ f: Float?) -> String {
        guard let f else { return "—" }
        return "\(Int((f * 100).rounded())) %"
    }

    static func ms(_ v: Float?) -> String {
        guard let v else { return "—" }
        return v < 10 ? String(format: "%.1f ms", v) : "\(Int(v.rounded())) ms"
    }

    static func bytes(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory)
    }

    static func diskBytes(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }

    /// Network speed in bits per second, Mbps style.
    static func bits(_ bps: Double) -> String {
        if bps >= 1_000_000_000 { return String(format: "%.2f Gbps", bps / 1_000_000_000) }
        if bps >= 1_000_000 { return String(format: bps >= 100_000_000 ? "%.0f Mbps" : "%.1f Mbps", bps / 1_000_000) }
        if bps >= 1_000 { return String(format: "%.0f kbps", bps / 1_000) }
        return "0 kbps"
    }

    static func bytesPerSec(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.0f MB/s", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0f KB/s", v / 1_000) }
        return "0 KB/s"
    }

    static func watts(_ w: Double?) -> String {
        guard let w else { return "—" }
        return String(format: w < 10 ? "%.1f W" : "%.0f W", w)
    }
}
