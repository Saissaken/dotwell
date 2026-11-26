import MonitorCore
import SwiftUI

/// The route to the primary ping target as five dots: this Mac, the router, the ISP, the internet and the server.
/// Each dot shows the round trip up to that point, colored by how healthy it is, so it is easy to see where
/// latency or loss starts. Clicking it lists every router on the way.
struct NetworkPathView: View {
    var path: NetworkPath
    var serverName: String
    @State private var expanded: Bool

    init(path: NetworkPath, serverName: String, expanded: Bool = false) {
        self.path = path
        self.serverName = serverName
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(path.segments) { segment in
                            node(segment)
                        }
                    }
                    verdictRow
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Hides the routers on the way" : "Shows every router on the way")
            if expanded {
                HopList(path: path, serverName: serverName)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Dots

    private func node(_ segment: NetworkPath.Segment) -> some View {
        let index = segment.stage.rawValue
        let incoming = index > 0 ? lineColor(segment) : .clear
        let outgoing = index + 1 < path.segments.count ? lineColor(path.segments[index + 1]) : .clear
        return VStack(spacing: 3) {
            ZStack {
                HStack(spacing: 0) {
                    Rectangle().fill(incoming)
                    Rectangle().fill(outgoing)
                }
                .frame(height: 2)
                Image(systemName: Self.symbol(segment.stage))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(dotColor(segment.level)))
            }
            Text(label(segment))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value(segment))
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(textColor(segment.level))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label(segment)), \(value(segment))")
    }

    private func label(_ segment: NetworkPath.Segment) -> String {
        switch segment.stage {
        case .mac: return "Mac"
        case .router: return "Router"
        case .isp: return segment.name ?? "ISP"
        case .internet: return "Internet"
        case .server: return serverName
        }
    }

    private func value(_ segment: NetworkPath.Segment) -> String {
        switch segment.stage {
        case .mac: return "You"
        case .server where segment.lossFraction == 1: return "No reply"
        default:
            guard segment.latencyMs != nil else { return "—" }
            return Format.msText(segment.latencyMs)
        }
    }

    static func symbol(_ stage: NetworkPath.Stage) -> String {
        switch stage {
        case .mac: return "laptopcomputer"
        case .router: return "wifi.router"
        case .isp: return "building.2"
        case .internet: return "globe"
        case .server: return "server.rack"
        }
    }

    private func lineColor(_ segment: NetworkPath.Segment) -> Color {
        segment.level.map { dotColor($0).opacity(0.6) } ?? Color.secondary.opacity(0.3)
    }

    // MARK: - Verdict

    private var verdictRow: some View {
        HStack(spacing: 5) {
            if let level = problemLevel {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(levelColor(level))
            }
            Text(verdictText)
                .foregroundStyle(problemLevel == nil ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var problemLevel: HealthLevel? {
        guard let level = path.segments.compactMap(\.level).max(), level != .ok else { return nil }
        return level
    }

    var verdictText: String {
        switch path.verdict {
        case .tracing: return "Tracing the route to \(serverName)…"
        case .healthy: return "No problems along the way"
        case .noReply: return "\(serverName) isn't answering"
        case .slow(let stage): return "Slow from \(place(stage))"
        case .losing(let stage): return "Packets lost at \(place(stage))"
        }
    }

    private func place(_ stage: NetworkPath.Stage) -> String {
        switch stage {
        case .mac, .router: return "your Wi-Fi or router"
        case .isp: return path[.isp].name.map { "your ISP, \($0)" } ?? "your ISP"
        case .internet: return "the internet, past your ISP"
        case .server: return serverName
        }
    }
}

func dotColor(_ level: HealthLevel?) -> Color {
    guard let level else { return Color.secondary.opacity(0.45) }
    return level == .ok ? .green : levelColor(level)
}

private func textColor(_ level: HealthLevel?) -> Color {
    guard let level, level != .ok else { return .primary }
    return levelColor(level)
}

/// Every router on the way, grouped by where it sits.
private struct HopList: View {
    var path: NetworkPath
    var serverName: String

    private struct Row: Identifiable {
        var segment: NetworkPath.Segment
        var hop: TraceHop
        var id: Int { hop.ttl }
    }

    private static let rowHeight: CGFloat = 17
    private static let maxHeight: CGFloat = 190

    var body: some View {
        let rows = path.segments.flatMap { segment in segment.hops.map { Row(segment: segment, hop: $0) } }
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(rows) { row(segment: $0.segment, hop: $0.hop) }
            }
        }
        .frame(height: min(CGFloat(max(rows.count, 1)) * Self.rowHeight, Self.maxHeight))
        .overlay {
            if rows.isEmpty {
                Text("No routers have answered yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(segment: NetworkPath.Segment, hop: TraceHop) -> some View {
        HStack(spacing: 6) {
            Text("\(hop.ttl)")
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Circle()
                .fill(dotColor(segment.level))
                .frame(width: 6, height: 6)
            Text(name(hop))
                .foregroundStyle(hop.isSilent ? Color.secondary : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if !hop.isSilent && hop.stats.lossFraction > 0 {
                Text("\(Format.percent(hop.stats.lossFraction).value)% lost")
                    .foregroundStyle(.secondary)
            }
            Text(hop.isSilent ? "" : Format.msText(hop.stats.averageMs))
                .frame(width: 48, alignment: .trailing)
        }
        .font(.caption)
        .monospacedDigit()
        .frame(height: Self.rowHeight)
    }

    private func name(_ hop: TraceHop) -> String {
        if hop.isDestination { return "\(serverName) · \(hop.address ?? "")" }
        guard let address = hop.address else { return "No reply (router hides itself)" }
        return hop.hostname ?? address
    }
}
