import SwiftUI
import MonitorCore

/// Rows shown in the popover. Problems (non-green) are listed first, in their own section.
enum Row: Hashable {
    case ping, cpu, memory, disk, power, network, thermal

    var kind: MetricKind {
        switch self {
        case .ping: return .ping
        case .cpu: return .cpu
        case .memory: return .memory
        case .disk: return .disk
        case .power: return .power
        case .network: return .network
        case .thermal: return .thermal
        }
    }
}

struct PopoverView: View {
    @ObservedObject var model: PopoverModel
    @State private var launchAtLogin = LoginItem.isEnabled

    private var snap: Snapshot { model.snapshot }

    private var allRows: [Row] {
        var rows: [Row] = [.ping, .cpu, .memory, .disk]
        if snap.power != nil { rows.append(.power) }
        rows.append(.network)
        return rows
    }

    private var problems: [Row] {
        var rows = allRows.filter { snap.level($0.kind) != .ok }
        if snap.level(.thermal) != .ok { rows.append(.thermal) }
        return rows.sorted { snap.level($0.kind) > snap.level($1.kind) }
    }

    var body: some View {
        let problemRows = problems
        let rest = allRows.filter { !problemRows.contains($0) }
        VStack(alignment: .leading, spacing: 10) {
            header(problemCount: problemRows.count)

            if !problemRows.isEmpty {
                SectionLabel(text: "Requiere atención")
                VStack(spacing: 6) {
                    ForEach(problemRows, id: \.self) { row($0) }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.06)))
                SectionLabel(text: "Resto")
            }

            VStack(spacing: 6) {
                ForEach(rest, id: \.self) { row($0) }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Header / footer

    private func header(problemCount: Int) -> some View {
        HStack(alignment: .center) {
            Circle().fill(color(for: snap.overall)).frame(width: 8, height: 8)
            Text(problemCount == 0 ? "Todo en orden" : problemCount == 1 ? "1 problema" : "\(problemCount) problemas")
                .font(.headline)
            Spacer()
            Picker("", selection: $model.range) {
                ForEach(HistoryRange.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 150)
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Abrir al iniciar sesión", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .onChange(of: launchAtLogin) { enabled in
                    if !LoginItem.setEnabled(enabled) { launchAtLogin = LoginItem.isEnabled }
                }
            Spacer()
            Button("Salir") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .controlSize(.small)
        }
        .font(.caption)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ row: Row) -> some View {
        let level = snap.level(row.kind)
        switch row {
        case .ping: pingRow(level: level)
        case .cpu:
            MetricRow(title: "CPU", value: Format.percent(snap.cpu), detail: nil, level: level,
                      values: history(SeriesKey.cpu), maxValue: 1)
        case .memory:
            MetricRow(title: "Memoria",
                      value: snap.memory.map { Format.bytes($0.usedBytes) } ?? "—",
                      detail: snap.memory.map { "de \(Format.bytes($0.totalBytes)) · presión \(pressureText($0.pressure))" },
                      level: level, values: history(SeriesKey.memory), maxValue: 1)
        case .disk:
            MetricRow(title: "Disco",
                      value: snap.disk.map { "\(Format.diskBytes($0.availableBytes)) libres" } ?? "—",
                      detail: "↓ \(Format.bytesPerSec(snap.diskReadBytesPerSec))  ↑ \(Format.bytesPerSec(snap.diskWriteBytesPerSec))",
                      level: level, values: history(SeriesKey.diskWrite), maxValue: nil)
        case .power:
            MetricRow(title: snap.power?.source == .adapter ? "Cargador" : "Batería",
                      value: Format.watts(snap.power?.watts),
                      detail: snap.power?.source == .adapter ? (snap.power?.isCharging == true ? "cargando" : "enchufada") : "consumo",
                      level: level, values: history(SeriesKey.power), maxValue: nil)
        case .network:
            MetricRow(title: "Red",
                      value: "↓ \(Format.bits(snap.networkDownBitsPerSec))",
                      detail: "↑ \(Format.bits(snap.networkUpBitsPerSec))",
                      level: level, values: history(SeriesKey.netDown), maxValue: nil,
                      secondary: history(SeriesKey.netUp))
        case .thermal:
            MetricRow(title: "Temperatura", value: thermalText(snap.thermal),
                      detail: "macOS está limitando el rendimiento", level: level, values: [], maxValue: nil)
        }
    }

    @ViewBuilder
    private func pingRow(level: HealthLevel) -> some View {
        let primary = snap.primaryPing
        VStack(alignment: .leading, spacing: 6) {
            MetricRow(title: "Ping · \(primary?.target.name ?? "—")",
                      value: primary?.stats.lastLost == true ? "sin respuesta" : Format.ms(primary?.stats.latestMs),
                      detail: primary.map { "pérdida \(Format.percent($0.stats.lossFraction)) · jitter \(Format.ms($0.stats.jitterMs))" },
                      level: level,
                      values: primary.map { history(SeriesKey.ping($0.index)) } ?? [], maxValue: nil)
            let others = snap.ping.filter { !$0.isPrimary }
            if !others.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 2) {
                    ForEach(others) { t in
                        HStack(spacing: 4) {
                            Text(t.target.name).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(t.stats.lastLost ? "—" : Format.ms(t.stats.latestMs)).monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
                .padding(.leading, 2)
            }
        }
    }

    private func history(_ key: String) -> [Float] { snap.history[key] ?? [] }

    private func pressureText(_ p: MemoryPressure) -> String {
        switch p {
        case .normal: return "normal"
        case .warning: return "alta"
        case .critical: return "crítica"
        }
    }

    private func thermalText(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return "normal"
        case .fair: return "templada"
        case .serious: return "alta"
        case .critical: return "crítica"
        @unknown default: return "—"
        }
    }
}

func color(for level: HealthLevel) -> Color {
    switch level {
    case .ok: return .green
    case .warning: return .yellow
    case .critical: return .red
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct MetricRow: View {
    var title: String
    var value: String
    var detail: String?
    var level: HealthLevel
    var values: [Float]
    var maxValue: Float?
    var secondary: [Float]? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if level != .ok {
                        Circle().fill(color(for: level)).frame(width: 6, height: 6)
                    }
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                Text(value).font(.system(.title3, design: .rounded).weight(.medium)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 150, alignment: .leading)
            ZStack {
                if let secondary {
                    Sparkline(values: secondary, maxValue: sharedMax, color: .orange)
                }
                Sparkline(values: values, maxValue: secondary == nil ? maxValue : sharedMax,
                          color: level == .ok ? .accentColor : color(for: level))
            }
            .frame(height: 30)
        }
        .frame(maxWidth: .infinity)
    }

    private var sharedMax: Float {
        max((values + (secondary ?? [])).max() ?? 1, 1)
    }
}
