import MonitorCore
import SwiftUI

/// The popover content: a header, then metric modules in the style of Control Center.
/// Modules that need attention move to the top, in their own group.
public struct PopoverView: View {
    @ObservedObject private var model: PopoverModel

    public init(model: PopoverModel) {
        self.model = model
    }

    private var snap: Snapshot { model.snapshot }

    public var body: some View {
        let modules = Module.visible(in: snap)
        let problems = modules.filter { snap.level($0.kind) != .ok }
            .sorted { snap.level($0.kind) > snap.level($1.kind) }
        let healthy = modules.filter { snap.level($0.kind) == .ok }

        VStack(alignment: .leading, spacing: 10) {
            header(problemCount: problems.count)
            if !problems.isEmpty {
                GroupLabel("Needs Attention")
                grid(problems)
                if !healthy.isEmpty { GroupLabel("Everything Else") }
            }
            grid(healthy)
        }
        .padding(12)
        .frame(width: 360)
    }

    // MARK: - Header

    private func header(problemCount: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: problemCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(problemCount == 0 ? Color.green : levelColor(snap.overall))
            Text(title(problemCount: problemCount))
                .font(.headline)
            Spacer(minLength: 8)
            Picker("Range", selection: $model.range) {
                ForEach(HistoryRange.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            Menu {
                Toggle(
                    "Open at Login",
                    isOn: Binding(get: { model.launchAtLogin }, set: { model.toggleLaunchAtLogin($0) }))
                if let checkForUpdates = model.checkForUpdates {
                    Button("Check for Updates…") { checkForUpdates() }
                }
                Divider()
                Button("Quit Dotwell") { model.quit?() }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 2)
    }

    private func title(problemCount: Int) -> String {
        switch problemCount {
        case 0: return "All Good"
        case 1: return "1 Issue"
        default: return "\(problemCount) Issues"
        }
    }

    // MARK: - Modules

    @ViewBuilder
    private func grid(_ modules: [Module]) -> some View {
        let rows = Module.rows(modules)
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(rows[i], id: \.self) { module($0) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func module(_ module: Module) -> some View {
        let level = snap.level(module.kind)
        switch module {
        case .ping:
            PingModule(snapshot: snap, level: level)
        case .cpu:
            MetricModule(
                symbol: "cpu", title: "CPU", level: level, reading: Format.percent(snap.cpu),
                caption: cpuCaption, topApp: topApp(\.cpu) { Format.processCPU($0.cpu) },
                values: history(SeriesKey.cpu), maxValue: 1)
        case .memory:
            MetricModule(
                symbol: "memorychip", title: "Memory", level: level,
                reading: snap.memory.map { Format.gigabytes($0.usedBytes) } ?? .none,
                caption: snap.memory.map(memoryCaption),
                topApp: topApp(\.memory) { Format.processMemory($0.memoryBytes) },
                values: history(SeriesKey.memory), maxValue: 1)
        case .power:
            MetricModule(
                symbol: powerSymbol, title: snap.power?.source == .adapter ? "Power Adapter" : "Battery",
                level: level, reading: Format.watts(snap.power?.watts), caption: powerCaption,
                topApp: topApp(\.power) { Format.watts($0.watts).text },
                values: history(SeriesKey.power), maxValue: nil)
        case .disk:
            MetricModule(
                symbol: "internaldrive", title: "Disk", level: level,
                reading: snap.disk.map { Format.storage($0.availableBytes) } ?? .none,
                caption: diskCaption, topApp: topApp(\.disk) { Format.bytesPerSec($0.diskBytesPerSec) },
                values: history(SeriesKey.diskRead), maxValue: nil, unitSuffix: "free")
        case .network:
            NetworkModule(snapshot: snap, down: history(SeriesKey.netDown), up: history(SeriesKey.netUp))
        case .thermal:
            MetricModule(
                symbol: "thermometer.medium", title: "Thermal", level: level,
                reading: Reading(value: thermalText, unit: ""), caption: thermalCaption,
                values: [], maxValue: nil)
        }
    }

    private func history(_ key: String) -> [Float] { snap.history[key] ?? [] }

    /// The top app line for a module, present only while per-app usage is sampled (popover open).
    private func topApp(
        _ key: KeyPath<TopApps, ProcessUsage?>, value: (ProcessUsage) -> String
    ) -> TopAppRow? {
        guard let apps = snap.topApps else { return nil }
        let app = apps[keyPath: key]
        return TopAppRow(app: app, value: app.map(value) ?? "", icon: app.map { model.icons.icon(for: $0.path) })
    }

    private func memoryCaption(_ memory: MemorySample) -> String {
        let total = Format.gigabytes(memory.totalBytes)
        let pressure: String
        switch memory.pressure {
        case .normal: pressure = "normal"
        case .warning: pressure = "high"
        case .critical: pressure = "critical"
        }
        return "of \(total.value) GB · pressure \(pressure)"
    }

    private var diskCaption: String {
        "Read \(Format.bytesPerSec(snap.diskReadBytesPerSec)) · Write \(Format.bytesPerSec(snap.diskWriteBytesPerSec))"
    }

    private var powerSymbol: String {
        snap.power?.source == .adapter ? "powerplug.fill" : "battery.75percent"
    }

    private var powerCaption: String {
        guard let power = snap.power else { return "" }
        switch power.source {
        case .battery: return "Drawing from battery"
        case .adapter: return power.isCharging ? "Charging" : "Plugged in"
        }
    }

    private var cpuCaption: String {
        let cores = "\(ProcessInfo.processInfo.activeProcessorCount) cores"
        guard let temperature = Format.temperature(snap.cpuTemperature) else { return cores }
        return "\(cores) · \(temperature)"
    }

    private var thermalCaption: String {
        guard let temperature = Format.temperature(snap.cpuTemperature) else { return "macOS is limiting performance" }
        return "Slowed down to cool · \(temperature)"
    }

    private var thermalText: String {
        switch snap.thermal {
        case .serious: return "High"
        case .critical: return "Critical"
        case .fair: return "Fair"
        default: return "Normal"
        }
    }
}

// MARK: - Layout model

enum Module: Hashable {
    case ping, cpu, memory, power, disk, network, thermal

    var kind: MetricKind {
        switch self {
        case .ping: return .ping
        case .cpu: return .cpu
        case .memory: return .memory
        case .power: return .power
        case .disk: return .disk
        case .network: return .network
        case .thermal: return .thermal
        }
    }

    /// Full-width modules take a row of their own.
    var isWide: Bool { self == .ping || self == .network }

    static func visible(in snap: Snapshot) -> [Module] {
        var modules: [Module] = [.ping, .cpu, .memory]
        if snap.power != nil { modules.append(.power) }
        modules.append(.disk)
        if snap.level(.thermal) != .ok { modules.append(.thermal) }
        modules.append(.network)
        return modules
    }

    /// Packs modules into rows: wide modules alone, others in pairs.
    static func rows(_ modules: [Module]) -> [[Module]] {
        var rows: [[Module]] = []
        var pending: [Module] = []
        for m in modules {
            if m.isWide {
                if !pending.isEmpty { rows.append(pending); pending = [] }
                rows.append([m])
            } else {
                pending.append(m)
                if pending.count == 2 { rows.append(pending); pending = [] }
            }
        }
        if !pending.isEmpty { rows.append(pending) }
        return rows
    }
}

func levelColor(_ level: HealthLevel) -> Color {
    switch level {
    case .ok: return .accentColor
    case .warning: return .orange
    case .critical: return .red
    }
}

// MARK: - Building blocks

struct GroupLabel: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }
}

/// Rounded "module" surface like Control Center's, tinted when the metric needs attention.
struct ModuleBackground: ViewModifier {
    var level: HealthLevel

    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(level == .ok ? Color.primary.opacity(0.06) : levelColor(level).opacity(0.14))
            )
    }
}

/// SF Symbol in a filled circle, as in Control Center.
struct SymbolBadge: View {
    var symbol: String
    var level: HealthLevel

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(levelColor(level)))
            .accessibilityHidden(true)
    }
}

struct ValueText: View {
    var reading: Reading
    var suffix: String?
    var level: HealthLevel = .ok
    var size: CGFloat = 20

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(reading.value)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(level == .ok ? Color.primary : levelColor(level))
            Text([reading.unit, suffix].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
                .font(.system(size: size * 0.6, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

struct MetricModule: View {
    var symbol: String
    var title: String
    var level: HealthLevel
    var reading: Reading
    var caption: String?
    var topApp: TopAppRow?
    var values: [Float]
    var maxValue: Float?
    var unitSuffix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                SymbolBadge(symbol: symbol, level: level)
                Text(title).font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            ValueText(reading: reading, suffix: unitSuffix, level: level)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            if let topApp { topApp }
            if !values.isEmpty {
                Spacer(minLength: 0)
                Sparkline(values: values, maxValue: maxValue, color: levelColor(level))
                    .frame(height: 22)
            }
        }
        .modifier(ModuleBackground(level: level))
    }
}

struct PingModule: View {
    var snapshot: Snapshot
    var level: HealthLevel

    var body: some View {
        let primary = snapshot.primaryPing
        let others = snapshot.ping.filter { !$0.isPrimary }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                SymbolBadge(symbol: "network", level: level)
                Text("Ping").font(.callout.weight(.medium))
                if let primary {
                    Text(primary.target.name).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if primary?.stats.lastLost == true {
                        ValueText(reading: Reading(value: "No reply", unit: ""), level: .critical, size: 26)
                    } else {
                        ValueText(reading: Format.ms(primary?.stats.latestMs), level: level, size: 26)
                    }
                    if let stats = primary?.stats {
                        Text(statsCaption(stats))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize()
                Sparkline(
                    values: primary.map { snapshot.history[SeriesKey.ping($0.index)] ?? [] } ?? [],
                    maxValue: nil, color: levelColor(level)
                )
                .frame(height: 40)
            }
            if !others.isEmpty {
                Divider().opacity(0.5)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    alignment: .leading, spacing: 4
                ) {
                    ForEach(others) { target in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(targetColor(target))
                                .frame(width: 6, height: 6)
                            Text(target.target.name)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(target.stats.lastLost ? "—" : Format.msText(target.stats.latestMs))
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .modifier(ModuleBackground(level: level))
    }

    private func statsCaption(_ stats: PingStats) -> String {
        "Loss \(Format.percent(stats.lossFraction).value)% · Jitter \(Format.msText(stats.jitterMs))"
    }

    private func targetColor(_ target: PingTargetState) -> Color {
        let level = Thresholds().ping(target.stats)
        return level == .ok ? .green : levelColor(level)
    }
}

struct NetworkModule: View {
    var snapshot: Snapshot
    var down: [Float]
    var up: [Float]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                SymbolBadge(symbol: "arrow.up.arrow.down", level: .ok)
                Text("Network").font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                Label {
                    ValueText(reading: Format.bits(snapshot.networkDownBitsPerSec))
                } icon: {
                    Image(systemName: "arrow.down").foregroundStyle(Color.accentColor)
                }
                Label {
                    ValueText(reading: Format.bits(snapshot.networkUpBitsPerSec))
                } icon: {
                    Image(systemName: "arrow.up").foregroundStyle(Color.purple)
                }
                Spacer(minLength: 0)
            }
            .font(.callout.weight(.semibold))
            let peak = max((down + up).max() ?? 1, 1)
            ZStack {
                Sparkline(values: up, maxValue: peak, color: .purple)
                Sparkline(values: down, maxValue: peak, color: .accentColor)
            }
            .frame(height: 26)
        }
        .modifier(ModuleBackground(level: .ok))
    }
}
