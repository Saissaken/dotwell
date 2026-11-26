import AppKit
import MonitorCore
import SwiftUI

/// What the ping rows can ask the app to do. Nil in previews, where the menu items do nothing.
struct PingActions {
    /// Traces the route to a row instead of the main host; nil goes back to the main host.
    var traceRoute: (Int?) -> Void
    /// Opens the settings that choose the host or region of a row.
    var changeHost: (Int) -> Void
    /// Makes a row the main host, the one the menu bar light follows.
    var makePrimary: (Int) -> Void
}

/// One secondary row of the Ping card, e.g. "AWS São Paulo 34 ms". Clicking it opens its detail; right-clicking
/// it offers its actions. Both use only readings the sampler already has, so they cost nothing extra.
struct PingRow: View {
    var target: PingTargetState
    var name: String
    var color: Color
    var context: PingRowContext

    @State private var showsDetail = false
    @State private var isHovered = false

    var body: some View {
        Button {
            showsDetail = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(target.stats.lastLost ? "—" : Format.msText(target.stats.latestMs))
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(isHovered || showsDetail ? 0.1 : 0))
            )
            .padding(.horizontal, -4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showsDetail, arrowEdge: .bottom) {
            PingDetail(target: target, name: name, context: context)
        }
        .contextMenu { PingRowMenu(target: target, context: context) }
        .accessibilityLabel("\(name), \(target.stats.lastLost ? "no reply" : Format.msText(target.stats.latestMs))")
        .accessibilityHint("Shows how this host is measured and its last minute")
        .help("Click for details, right-click for more")
    }
}

/// What a row's detail and menu need to know beyond the row itself.
struct PingRowContext {
    var thresholds: Thresholds
    /// Index of the row the route above is traced to.
    var pathIndex: Int?
    var actions: PingActions?
}

/// The popover behind a ping row: what is measured and how, and the last minute of readings.
struct PingDetail: View {
    var target: PingTargetState
    var name: String
    var context: PingRowContext

    var body: some View {
        let stats = target.minuteStats
        let level = context.thresholds.ping(stats)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(name).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if target.isPrimary {
                    Text("Main Host")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                ForEach(PingDetail.facts(for: target), id: \.label) { fact in
                    GridRow {
                        Text(fact.label).foregroundStyle(.secondary)
                        Text(fact.value)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.caption)

            Divider()
            Text(PingDetail.windowTitle(target))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(PingDetail.figures(stats), id: \.label) { figure in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(figure.label).font(.caption2).foregroundStyle(.secondary)
                        Text(figure.value).font(.caption.weight(.medium)).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Sparkline(
                values: target.lastMinute, maxValue: nil, color: levelColor(level),
                capacity: max(2, 60 / max(1, target.probeIntervalSeconds)))
                .frame(height: 34)
                .environment(\.chartMotion, nil)
                .overlay {
                    if target.lastMinute.filter({ $0 >= 0 }).isEmpty {
                        Text(target.lastMinute.isEmpty ? "Waiting for readings…" : "No replies")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

            Divider()
            Text("Right-click for more")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 270)
    }

    struct Line {
        var label: String
        var value: String
    }

    /// Host, address and method, in plain words.
    static func facts(for target: PingTargetState) -> [Line] {
        let t = target.target
        var lines: [Line] = []
        if t.isGateway {
            lines.append(Line(label: "Host", value: "Your Wi-Fi or Ethernet router"))
        } else if t.isISP {
            lines.append(Line(label: "Host", value: "First router of your internet provider"))
        } else if t.isDNS {
            lines.append(Line(label: "Host", value: "The DNS server your Mac uses"))
        } else if t.host != target.address {
            lines.append(Line(label: "Host", value: t.host))
        }
        if let region = CloudRegion.all.first(where: { $0.host == t.host }) {
            lines.append(Line(label: "Region", value: region.code))
        }
        lines.append(Line(label: "IP", value: target.address ?? (t.isISP ? "Looking for it…" : "Looking it up…")))
        lines.append(Line(label: "Measured", value: "\(method(t.method)), \(every(target.probeIntervalSeconds))"))
        return lines
    }

    static func method(_ method: PingTarget.Method) -> String {
        switch method {
        case .icmp: return "Ping (ICMP echo)"
        case .tcp(let port): return "Time to open a connection (TCP port \(port))"
        case .https: return "Time to answer a small HTTPS request"
        case .dns: return "Time to answer a DNS query"
        }
    }

    static func every(_ seconds: Int) -> String {
        seconds == 1 ? "every second" : "every \(seconds) seconds"
    }

    /// "Last minute", or how long the readings cover so far.
    static func windowTitle(_ target: PingTargetState) -> String {
        let covered = target.lastMinute.count * target.probeIntervalSeconds
        guard covered > 0, covered < 55 else { return "Last Minute" }
        return "Last \(covered) Seconds"
    }

    static func figures(_ stats: PingStats) -> [Line] {
        guard stats.averageMs != nil || stats.lossFraction > 0 else {
            return ["Average", "Min", "Max", "Loss", "Jitter"].map { Line(label: $0, value: "—") }
        }
        return [
            Line(label: "Average", value: Format.msText(stats.averageMs)),
            Line(label: "Min", value: Format.msText(stats.minMs)),
            Line(label: "Max", value: Format.msText(stats.maxMs)),
            Line(label: "Loss", value: Format.percent(stats.lossFraction).text),
            Line(label: "Jitter", value: Format.msText(stats.jitterMs)),
        ]
    }
}

/// The right-click menu of a ping row.
struct PingRowMenu: View {
    var target: PingTargetState
    var context: PingRowContext

    var body: some View {
        let t = target.target
        Button("Copy IP Address") { copy(target.address) }
            .disabled(target.address == nil)
        if !t.isDiscovered, t.host != target.address {
            Button("Copy Host Name") { copy(t.host) }
        }
        if !t.isGateway {
            Divider()
            if context.pathIndex == target.index, !target.isPrimary {
                Button("Trace Route to Main Host") { context.actions?.traceRoute(nil) }
            } else {
                Button("Trace Route to This Host") { context.actions?.traceRoute(target.index) }
                    .disabled(context.pathIndex == target.index || (t.isDiscovered && target.address == nil))
            }
        }
        Divider()
        if !t.isDiscovered {
            Button(CloudRegion.all.contains { $0.host == t.host } ? "Change Region…" : "Change Host…") {
                context.actions?.changeHost(target.index)
            }
        }
        Button("Use as Main Host") { context.actions?.makePrimary(target.index) }
            .disabled(target.isPrimary)
    }

    private func copy(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
