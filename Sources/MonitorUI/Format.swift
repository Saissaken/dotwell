import Foundation

/// A number and its unit, displayed with different weights.
struct Reading: Equatable {
    var value: String
    var unit: String

    static let none = Reading(value: "—", unit: "")

    /// Single-string form, e.g. "2.1 W".
    var text: String { unit.isEmpty ? value : "\(value) \(unit)" }
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
        ms(value).text
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

    /// Network speed in the unit chosen in Settings.
    static func network(_ bitsPerSec: Double, unit: NetworkUnit) -> Reading {
        switch unit {
        case .bits: return bits(bitsPerSec)
        case .bytes: return bytes(bitsPerSec / 8)
        }
    }

    /// Network speed in bytes per second, like download progress in Finder.
    static func bytes(_ bytesPerSec: Double) -> Reading {
        if bytesPerSec >= 1_000_000_000 {
            return Reading(value: String(format: "%.2f", bytesPerSec / 1e9), unit: "GB/s")
        }
        if bytesPerSec >= 1_000_000 {
            let format = bytesPerSec >= 100e6 ? "%.0f" : "%.1f"
            return Reading(value: String(format: format, bytesPerSec / 1e6), unit: "MB/s")
        }
        return Reading(value: String(format: "%.0f", bytesPerSec / 1e3), unit: "KB/s")
    }

    static func bytesPerSec(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.0f MB/s", value / 1e6) }
        return String(format: "%.0f KB/s", value / 1e3)
    }

    /// Temperature in the unit the user prefers (System Settings → Language & Region), e.g. "52°C".
    static func temperature(_ celsius: Float?) -> String? {
        guard let celsius else { return nil }
        return temperatureFormatter.string(from: Measurement(value: Double(celsius), unit: UnitTemperature.celsius))
    }

    /// Internal so tests and screenshots can pin a locale.
    static let temperatureFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter
    }()

    /// Per-process CPU as Activity Monitor shows it, where 100 % is one full core.
    static func processCPU(_ fraction: Float) -> String {
        let percent = fraction * 100
        return percent < 10 ? String(format: "%.1f%%", percent) : String(format: "%.0f%%", percent)
    }

    /// Per-process memory in binary units like Activity Monitor: "640 MB", "2.4 GB".
    static func processMemory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576.0
        return mb < 1024 ? String(format: "%.0f MB", mb) : String(format: "%.1f GB", mb / 1024)
    }

    static func watts(_ watts: Double?) -> Reading {
        guard let watts else { return .none }
        return Reading(value: String(format: watts < 10 ? "%.1f" : "%.0f", watts), unit: "W")
    }
}
