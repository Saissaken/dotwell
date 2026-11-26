import Foundation

/// A number and its unit, displayed with different weights.
struct Reading: Equatable {
    var value: String
    var unit: String

    static let none = Reading(value: "—", unit: "")

    /// Single-string form, e.g. "2.1 W".
    var text: String { unit.isEmpty ? value : "\(value) \(unit)" }
}

/// Formats every value with at most three significant digits ("9.9", "99.9", "999"), switching
/// to the next unit instead of growing ("998 KB/s", then "1.0 MB/s"). Each label then has a known
/// maximum width, so the popover can keep one fixed font size instead of shrinking text to fit.
enum Format {
    /// At most three significant digits: one decimal below 100, none from 100 to 999.
    /// Zero is shown as "0" rather than "0.0".
    static func significant(_ value: Double) -> String {
        let value = max(0, value)
        let tenths = (value * 10).rounded()
        if tenths == 0 { return "0" }
        if tenths < 1000 { return String(format: "%.1f", tenths / 10) }
        return String(format: "%.0f", value.rounded())
    }

    /// Scales `value` (given in `units[0]`) up by `step` until it shows at most three digits.
    static func scaled(_ value: Double, units: [String], step: Double = 1000) -> Reading {
        var value = max(0, value.isFinite ? value : 0)
        var index = 0
        while index < units.count - 1, value.rounded() >= 1000 {
            value /= step
            index += 1
        }
        return Reading(value: significant(value), unit: units[index])
    }

    static func percent(_ fraction: Float?) -> Reading {
        guard let fraction else { return .none }
        return Reading(value: "\(Int((fraction * 100).rounded()))", unit: "%")
    }

    /// Latency: "4.2 ms", "45 ms", "999 ms", then "1.2 s". Whole milliseconds above 10 ms,
    /// since finer steps are only noise at that point.
    static func ms(_ value: Float?) -> Reading {
        guard let value else { return .none }
        let ms = Double(max(0, value))
        if ms.rounded() >= 1000 { return Reading(value: significant(ms / 1000), unit: "s") }
        let text = ms < 9.95 ? String(format: "%.1f", ms) : String(format: "%.0f", ms.rounded())
        return Reading(value: text, unit: "ms")
    }

    /// Short "12 ms" form for secondary labels.
    static func msText(_ value: Float?) -> String {
        ms(value).text
    }

    /// Memory size in binary units (shown as "GB" like Activity Monitor does): "11.4 GB", "128 GB".
    static func gigabytes(_ bytes: UInt64) -> Reading {
        scaled(Double(bytes) / 1_073_741_824.0, units: ["GB", "TB"], step: 1024)
    }

    /// Storage size in decimal units, like Finder and System Settings: "249 GB", "1.2 TB".
    static func storage(_ bytes: UInt64) -> Reading {
        scaled(Double(bytes) / 1e9, units: ["GB", "TB", "PB"])
    }

    /// Network speed in bits per second: "850 kbps", "12.3 Mbps", "1.2 Gbps".
    static func bits(_ bps: Double) -> Reading {
        scaled(bps / 1e3, units: ["kbps", "Mbps", "Gbps", "Tbps"])
    }

    /// Transfer rate in bytes per second: "773 KB/s", "1.2 MB/s", "123 MB/s".
    static func bytes(_ bytesPerSec: Double) -> Reading {
        scaled(bytesPerSec / 1e3, units: ["KB/s", "MB/s", "GB/s", "TB/s"])
    }

    /// Network speed in the unit chosen in Settings.
    static func network(_ bitsPerSec: Double, unit: NetworkUnit) -> Reading {
        switch unit {
        case .bits: return bits(bitsPerSec)
        case .bytes: return bytes(bitsPerSec / 8)
        }
    }

    static func bytesPerSec(_ value: Double) -> String {
        bytes(value).text
    }

    /// The disk module's caption, e.g. "R 123 MB/s · W 773 KB/s". "Read" and "Write" spelled out
    /// don't fit a half-width module at the caption size once both values have three digits.
    static func diskIO(read: Double, write: Double) -> String {
        "R \(bytesPerSec(read)) · W \(bytesPerSec(write))"
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

    /// An app's CPU use. `fraction` is in cores (1.5 = one and a half cores busy); `.wholeMac` divides it by
    /// `cores` so it reads on the same scale as the CPU card's total.
    static func processCPU(
        _ fraction: Float, scale: ProcessCPUScale = .perCore,
        cores: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> String {
        let percent = (scale == .wholeMac ? fraction / Float(max(cores, 1)) : fraction) * 100
        return percent < 9.95 ? String(format: "%.1f%%", percent) : String(format: "%.0f%%", percent)
    }

    /// Per-process memory in binary units like Activity Monitor: "640 MB", "2.4 GB".
    static func processMemory(_ bytes: UInt64) -> String {
        scaled(Double(bytes) / 1_048_576.0, units: ["MB", "GB", "TB"], step: 1024).text
    }

    static func watts(_ watts: Double?) -> Reading {
        guard let watts else { return .none }
        return Reading(value: significant(watts), unit: "W")
    }
}
