import MonitorCore
import SwiftUI

/// When each metric turns the status light yellow or red.
struct AlertSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            alertToggle(.ping, "Alert when ping is slow or drops replies")
            LabeledContent("Latency:") {
                ThresholdPair(
                    warning: value(\.pingWarningMs, partner: \.pingCriticalMs, isLower: true),
                    critical: value(\.pingCriticalMs, partner: \.pingWarningMs, isLower: false),
                    range: 1...2000, step: 10, unit: "ms")
            }
            .disabled(!isOn(.ping))
            LabeledContent("Packet loss:") {
                ThresholdPair(
                    warning: value(\.pingLossWarning, partner: \.pingLossCritical, isLower: true, scale: 100),
                    critical: value(\.pingLossCritical, partner: \.pingLossWarning, isLower: false, scale: 100),
                    range: 1...100, step: 1, unit: "%")
            }
            .disabled(!isOn(.ping))
            Divider().padding(.vertical, 4)

            alertToggle(.cpu, "Alert when the CPU stays busy")
            LabeledContent("Usage above:") {
                ThresholdPair(
                    warning: value(\.cpuWarning, partner: \.cpuCritical, isLower: true, scale: 100),
                    critical: value(\.cpuCritical, partner: \.cpuWarning, isLower: false, scale: 100),
                    range: 10...100, step: 5, unit: "%")
            }
            .disabled(!isOn(.cpu))
            SettingNote("Yellow after 30 seconds above the limit, red after a minute.")
            Divider().padding(.vertical, 4)

            alertToggle(.memory, "Alert when macOS reports memory pressure")
            Divider().padding(.vertical, 4)

            alertToggle(.disk, "Alert when the startup disk is filling up")
            LabeledContent("Free space below:") {
                ThresholdPair(
                    warning: value(\.diskFreeWarning, partner: \.diskFreeCritical, isLower: false, scale: 100),
                    critical: value(\.diskFreeCritical, partner: \.diskFreeWarning, isLower: true, scale: 100),
                    range: 1...50, step: 1, unit: "%")
            }
            .disabled(!isOn(.disk))
            Divider().padding(.vertical, 4)

            alertToggle(.power, "Alert when the battery drains fast")
            LabeledContent("Drawing more than:") {
                HStack(spacing: 6) {
                    LevelDot(color: .orange)
                    NumberField(value: batteryWatts, range: 5...100, step: 5)
                    Text("W").foregroundStyle(.secondary)
                }
            }
            .disabled(!isOn(.power))
            Divider().padding(.vertical, 4)

            alertToggle(.thermal, "Alert when macOS slows the Mac down to cool it")
            HStack {
                Spacer()
                Button("Restore Defaults") { settings.restoreDefaultAlerts() }
            }
            .padding(.top, 8)
        }
        .formStyle(.columns)
    }

    private func isOn(_ kind: MetricKind) -> Bool { settings.alerts.contains(kind) }

    private func alertToggle(_ kind: MetricKind, _ title: String) -> some View {
        LabeledContent("\(kind.settingsTitle):") {
            Toggle(
                title,
                isOn: Binding(
                    get: { settings.alerts.contains(kind) },
                    set: { enabled in
                        if enabled { settings.alerts.insert(kind) } else { settings.alerts.remove(kind) }
                    }))
        }
    }

    /// A threshold shown as a number, scaled for display (fractions as percentages). Moving one
    /// limit past its partner drags the partner along, so yellow always comes before red.
    private func value(
        _ key: WritableKeyPath<Thresholds, Float>, partner: WritableKeyPath<Thresholds, Float>,
        isLower: Bool, scale: Double = 1
    ) -> Binding<Double> {
        Binding(
            get: { (Double(settings.thresholds[keyPath: key]) * scale).rounded() },
            set: { newValue in
                var thresholds = settings.thresholds
                let value = Float(newValue / scale)
                thresholds[keyPath: key] = value
                if isLower, thresholds[keyPath: partner] < value { thresholds[keyPath: partner] = value }
                if !isLower, thresholds[keyPath: partner] > value { thresholds[keyPath: partner] = value }
                settings.thresholds = thresholds
            })
    }

    private var batteryWatts: Binding<Double> {
        Binding(
            get: { settings.thresholds.batteryDrawWarningWatts },
            set: { settings.thresholds.batteryDrawWarningWatts = $0 })
    }
}

extension MetricKind {
    var settingsTitle: String {
        switch self {
        case .ping: return "Ping"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .power: return "Battery"
        case .network: return "Network"
        case .thermal: return "Heat"
        case .gpu: return "GPU"
        }
    }
}

/// Yellow and red limits side by side.
private struct ThresholdPair: View {
    @Binding var warning: Double
    @Binding var critical: Double
    var range: ClosedRange<Double>
    var step: Double
    var unit: String

    var body: some View {
        HStack(spacing: 6) {
            LevelDot(color: .orange)
            NumberField(value: $warning, range: range, step: step)
                .accessibilityLabel("Yellow")
            Spacer().frame(width: 10)
            LevelDot(color: .red)
            NumberField(value: $critical, range: range, step: step)
                .accessibilityLabel("Red")
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

private struct LevelDot: View {
    var color: Color

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
    }
}

/// A short number field with a stepper, clamped to `range`.
private struct NumberField: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double

    var body: some View {
        let clamped = Binding(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) })
        HStack(spacing: 2) {
            TextField("", value: clamped, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .labelsHidden()
            Stepper("", value: clamped, in: range, step: step)
                .labelsHidden()
        }
    }
}
