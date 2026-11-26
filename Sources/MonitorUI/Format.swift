import Foundation

/// A number and its unit, displayed with different weights.
struct Reading: Equatable {
    var value: String
    var unit: String

    static let none = Reading(value: "—", unit: "")
}

enum Format {
    static func percent(_ fraction: Float?) -> Reading {
        guard let fraction else { return .none }
        return Reading(value: "\(Int((fraction * 100).rounded()))", unit: "%")
    }

    static func ms(_ value: Float?) -> Reading {
        guard let value else { return .none }
        let text = value < 10 ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
        return Reading(value: text, unit: "ms")
    }

    /// Short "12 ms" form for secondary labels.
    static func msText(_ value: Float?) -> String {
        let r = ms(value)
        return r.unit.isEmpty ? r.value : "\(r.value) \(r.unit)"
    }

    /// Memory size in binary gigabytes (GiB, shown as "GB" like Activity Monitor does).
    static func gigabytes(_ bytes: UInt64) -> Reading {
        let gb = Double(bytes) / 1_073_741_824.0
        return Reading(value: gb >= 100 ? String(format: "%.0f", gb) : String(format: "%.1f", gb), unit: "GB")
    }

    /// Storage size in decimal units with one decimal place, matching Finder and System Settings,
    /// so "248.6 GB" can be compared directly with the "248.62 GB" macOS shows.
    static func storage(_ bytes: UInt64) -> Reading {
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1000 { return Reading(value: String(format: "%.2f", gb / 1000), unit: "TB") }
        return Reading(value: String(format: "%.1f", gb), unit: "GB")
    }

    /// Network speed in bits per second.
    static func bits(_ bps: Double) -> Reading {
        if bps >= 1_000_000_000 { return Reading(value: String(format: "%.2f", bps / 1e9), unit: "Gbps") }
        if bps >= 1_000_000 {
            return Reading(value: String(format: bps >= 100e6 ? "%.0f" : "%.1f", bps / 1e6), unit: "Mbps")
        }
        return Reading(value: String(format: "%.0f", bps / 1e3), unit: "kbps")
    }

    static func bytesPerSec(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.0f MB/s", value / 1e6) }
        return String(format: "%.0f KB/s", value / 1e3)
    }

    static func watts(_ watts: Double?) -> Reading {
        guard let watts else { return .none }
        return Reading(value: String(format: watts < 10 ? "%.1f" : "%.0f", watts), unit: "W")
    }
}
