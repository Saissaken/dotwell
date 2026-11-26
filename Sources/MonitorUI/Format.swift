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

    static func gigabytes(_ bytes: UInt64, decimal: Bool = false) -> Reading {
        let divisor = decimal ? 1_000_000_000.0 : 1_073_741_824.0
        let gb = Double(bytes) / divisor
        return Reading(value: gb >= 100 ? String(format: "%.0f", gb) : String(format: "%.1f", gb), unit: "GB")
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
