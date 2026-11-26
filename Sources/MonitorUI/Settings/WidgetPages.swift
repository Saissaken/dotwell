import MonitorCore
import SwiftUI

/// One page per card of the popover: whether it shows, its options, and its alert, all in one place.
struct WidgetPage: View {
    var module: Module
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                PageHeader(page: .widget(module), summary: module.settingsSummary) {
                    Toggle("Show in panel", isOn: visible)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help("Shows or hides the \(module.settingsTitle) card in the panel.\(hiddenNote)")
                }
            }
            switch module {
            case .ping: PingSettings(settings: settings)
            case .cpu: CPUSettings(settings: settings, topApp: topApp)
            case .gpu: GPUSettings(topApp: topApp)
            case .memory: MemorySettings(settings: settings, topApp: topApp)
            case .power: BatterySettings(settings: settings, topApp: topApp)
            case .disk: DiskSettings(settings: settings, topApp: topApp)
            case .network: NetworkSettings(settings: settings)
            }
        }
        .formStyle(.grouped)
    }

    private var hiddenNote: String {
        module == .ping ? " Hidden and with its alert off, Dotwell stops pinging altogether." : ""
    }

    private var visible: Binding<Bool> { widgetBinding(\.isVisible) }

    /// The "busiest app" switch, for cards that have one.
    private var topApp: some View {
        SwitchRow(
            title: "Show the busiest app",
            detail: "Names the app using the most \(module.resourceName) while the panel is open.",
            help: "Adds a line with the app using the most \(module.resourceName) right now; click it to see the "
                + "top five and copy their process IDs. Dotwell only looks at apps while the panel is open.",
            isOn: widgetBinding(\.showsTopApp)
        )
        .disabled(!settings.isVisible(module))
    }

    private func widgetBinding(_ key: WritableKeyPath<WidgetSetting, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.widgets.first { $0.module == module }?[keyPath: key] ?? true },
            set: { newValue in
                guard let index = settings.widgets.firstIndex(where: { $0.module == module }) else { return }
                settings.widgets[index][keyPath: key] = newValue
            })
    }
}

extension Module {
    /// What the busiest app uses the most of.
    var resourceName: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "memory"
        case .power: return "energy"
        case .disk: return "disk"
        case .ping, .network: return "network"
        }
    }
}

// MARK: - Alerts

/// Shared plumbing for the Alert section of each page.
@MainActor
struct AlertBindings {
    var settings: AppSettings

    func isOn(_ kind: MetricKind) -> Binding<Bool> {
        Binding(
            get: { settings.alerts.contains(kind) },
            set: { enabled in
                if enabled { settings.alerts.insert(kind) } else { settings.alerts.remove(kind) }
            })
    }

    /// A threshold shown as a number, scaled for display (fractions as percentages). Moving one
    /// limit past its partner drags the partner along, so yellow always comes before red.
    func limit(
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
}

/// A row with a yellow and a red limit.
struct LimitsRow: View {
    var title: String
    var help: String
    @Binding var warning: Double
    @Binding var critical: Double
    var range: ClosedRange<Double>
    var step: Double
    var unit: String

    var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                LimitField(color: .orange, value: $warning, range: range, step: step, unit: unit)
                    .accessibilityLabel("Yellow")
                LimitField(color: .red, value: $critical, range: range, step: step, unit: unit)
                    .accessibilityLabel("Red")
            }
        } label: {
            Text(title)
        }
        .help(help)
    }
}

// MARK: - CPU

private struct CPUSettings<TopApp: View>: View {
    @ObservedObject var settings: AppSettings
    var topApp: TopApp

    var body: some View {
        let alerts = AlertBindings(settings: settings)
        Section("Card") {
            topApp
            Picker(selection: $settings.processCPUScale) {
                Text("Share of the whole Mac").tag(ProcessCPUScale.wholeMac)
                Text("Share of one core").tag(ProcessCPUScale.perCore)
            } label: {
                SettingLabel("Show app CPU use as", detail: "One core matches Activity Monitor and can go over 100%.")
            }
            .help(
                "Share of the whole Mac uses the same scale as the card's total, so apps add up to it. Share of one "
                    + "core is how Activity Monitor counts: an app busy on 4 cores shows 400%."
            )
            .disabled(!settings.showsTopApp(.cpu))
            SwitchRow(
                title: "Show temperature and fan speed",
                detail: "From the Mac's own sensors. Not every Mac has them.",
                help: "Shows the average temperature of the CPU cores and the fan speed next to the core count. "
                    + "Off, Dotwell doesn't read the sensors at all.",
                isOn: $settings.showsCPUTemperature)
        }
        Section {
            SwitchRow(
                title: "Warn when macOS slows the Mac down",
                detail: "Adds \"Slowed down to cool\" to this card and turns the light yellow or red.",
                help: "When the Mac gets too hot, macOS lowers its speed to cool it down (thermal throttling). "
                    + "This is separate from how busy the CPU is: a Mac in the sun or charging can be throttled "
                    + "while doing little.",
                isOn: alerts.isOn(.thermal))
        } header: {
            Text("Slowing Down to Cool")
        } footer: {
            Footer(
                "This used to be the Thermal card. macOS only does it when the Mac is very hot, so most days it "
                    + "never shows.")
        }
        Section {
            SwitchRow(
                title: "Alert when the CPU stays busy",
                detail: nil,
                help: "Turns the menu bar light yellow or red when the CPU stays above these limits.",
                isOn: alerts.isOn(.cpu))
            LimitsRow(
                title: "Usage above",
                help: "Yellow above the first limit, red above the second, as a share of all cores.",
                warning: alerts.limit(\.cpuWarning, partner: \.cpuCritical, isLower: true, scale: 100),
                critical: alerts.limit(\.cpuCritical, partner: \.cpuWarning, isLower: false, scale: 100),
                range: 10...100, step: 5, unit: "%"
            )
            .disabled(!settings.alerts.contains(.cpu))
        } header: {
            Text("Alert")
        } footer: {
            Footer("Yellow after 30 seconds above the limit, red after a minute, so a short spike never alerts.")
        }
    }
}

// MARK: - Memory

private struct MemorySettings<TopApp: View>: View {
    @ObservedObject var settings: AppSettings
    var topApp: TopApp

    var body: some View {
        Section("Card") { topApp }
        Section {
            SwitchRow(
                title: "Alert when memory runs short",
                detail: nil,
                help: "Uses the memory pressure macOS itself reports, like Activity Monitor's graph: "
                    + "yellow when it's high, red when it's critical.",
                isOn: AlertBindings(settings: settings).isOn(.memory))
        } header: {
            Text("Alert")
        } footer: {
            Footer(
                "Used memory alone says little: macOS fills spare memory on purpose. Pressure is what slows "
                    + "you down.")
        }
    }
}

// MARK: - GPU

private struct GPUSettings<TopApp: View>: View {
    var topApp: TopApp

    var body: some View {
        Section {
            topApp
        } header: {
            Text("Card")
        } footer: {
            Footer(
                "The GPU has no alert: a GPU at 100% during a game or an export is doing its job. Dotwell only "
                    + "reads it while the panel is open.")
        }
    }
}

// MARK: - Disk

private struct DiskSettings<TopApp: View>: View {
    @ObservedObject var settings: AppSettings
    var topApp: TopApp

    var body: some View {
        let alerts = AlertBindings(settings: settings)
        Section("Card") { topApp }
        Section {
            SwitchRow(
                title: "Alert when the startup disk is filling up",
                detail: nil,
                help: "Turns the menu bar light yellow or red when free space drops below these limits.",
                isOn: alerts.isOn(.disk))
            LimitsRow(
                title: "Free space below",
                help: "Yellow below the first limit, red below the second, as a share of the disk.",
                warning: alerts.limit(\.diskFreeWarning, partner: \.diskFreeCritical, isLower: false, scale: 100),
                critical: alerts.limit(\.diskFreeCritical, partner: \.diskFreeWarning, isLower: true, scale: 100),
                range: 1...50, step: 1, unit: "%"
            )
            .disabled(!settings.alerts.contains(.disk))
        } header: {
            Text("Alert")
        }
    }
}

// MARK: - Battery

private struct BatterySettings<TopApp: View>: View {
    @ObservedObject var settings: AppSettings
    var topApp: TopApp

    var body: some View {
        let alerts = AlertBindings(settings: settings)
        Section("Card") { topApp }
        Section {
            SwitchRow(
                title: "Alert when the battery drains fast",
                detail: nil,
                help: "Turns the menu bar light yellow while the Mac draws more than this from its battery.",
                isOn: alerts.isOn(.power))
            LabeledContent {
                LimitField(
                    color: .orange,
                    value: Binding(
                        get: { settings.thresholds.batteryDrawWarningWatts },
                        set: { settings.thresholds.batteryDrawWarningWatts = $0 }),
                    range: 5...100, step: 5, unit: "W")
            } label: {
                Text("Drawing more than")
            }
            .help("Watts drawn from the battery. Light use is usually under 10 W.")
            .disabled(!settings.alerts.contains(.power))
        } header: {
            Text("Alert")
        } footer: {
            Footer("Only on battery, after 30 seconds above the limit. Plugged in, it never alerts.")
        }
    }
}

// MARK: - Network

private struct NetworkSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Section("Speed") {
            Picker(selection: $settings.networkUnit) {
                Text("Megabits per second (Mbps)").tag(NetworkUnit.bits)
                Text("Megabytes per second (MB/s)").tag(NetworkUnit.bytes)
            } label: {
                SettingLabel("Show speed in", detail: "Mbps matches internet plans; MB/s matches downloads in Finder.")
            }
            .help(
                "Internet plans and speed tests use bits (Mbps). Browsers and Finder show downloads in bytes "
                    + "(MB/s), which is 8 times smaller for the same speed.")
        }
        Section {
            SwitchRow(
                title: "Show local and public IP addresses",
                detail: "Turn off before sharing your screen.",
                help: "Shows this Mac's address on your network and the one the internet sees. Click one to copy "
                    + "it. When off, Dotwell never looks up your public address.",
                isOn: $settings.showsIPAddresses)
        } header: {
            Text("IP Addresses")
        } footer: {
            Footer("The public address comes from Cloudflare (1.1.1.1), only while the panel is open.")
        }
        Section {
            Text("A slow connection already shows up in Ping, which measures it reliably.")
                .foregroundStyle(.secondary)
        } header: {
            Text("Alert")
        }
    }
}

/// Explanation under a section, in System Settings' footnote style.
struct Footer: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
