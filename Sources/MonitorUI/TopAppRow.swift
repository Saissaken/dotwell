import AppKit
import MonitorCore
import SwiftUI
import UniformTypeIdentifiers

/// One compact line inside a metric module: the app using the most of that resource.
/// Clicking it opens a small popover with the top apps and their process IDs.
/// With no app yet, the line keeps its height so the popover doesn't change size.
struct TopAppRow: View {
    var list: TopAppsList
    @State private var showsList = false
    @State private var isHovered = false

    private var app: ProcessUsage? { list.apps.first }

    var body: some View {
        Button {
            showsList = true
        } label: {
            line
        }
        .buttonStyle(.plain)
        .disabled(app == nil)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showsList, arrowEdge: .bottom) { list }
        .contextMenu {
            if let app, app.pid > 0 {
                AppContextMenu(app: app) { AppActions.copy(String(app.pid)) }
            }
        }
        .opacity(app == nil ? 0 : 1)
        .accessibilityLabel(app.map { "Top app: \($0.name), \(list.value($0))" } ?? "")
        .accessibilityHint("Shows the top apps and their process IDs")
        .help(app.map { "Using the most right now: \($0.name). Click to see the top apps." } ?? "")
    }

    private var line: some View {
        HStack(spacing: 5) {
            AppIcon(image: app.map { list.icons.icon(for: $0.path) })
            Text(app?.name ?? " ")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(app.map(list.value) ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .font(.caption)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(isHovered || showsList ? 0.1 : 0))
        )
        .padding(.horizontal, -4)
        .contentShape(Rectangle())
    }
}

/// The popover behind a top app line: the apps using the most of one resource, largest first.
/// Clicking an app copies its process ID, e.g. for `kill`; right-clicking it offers more, such as Quit.
struct TopAppsList: View {
    /// "Top Apps by CPU".
    var title: String
    /// Header of the value column, e.g. "CPU".
    var column: String
    var apps: [ProcessUsage]
    var value: (ProcessUsage) -> String
    var icons: IconCache

    @State private var hovered: String?
    @State private var copied: pid_t?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                Text("PID").frame(width: Self.pidWidth, alignment: .trailing)
                Text(column).frame(minWidth: Self.valueWidth, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
            .accessibilityHidden(true)

            if apps.isEmpty {
                Text("Nothing is using this right now")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            ForEach(apps) { app in
                row(app)
            }

            Divider().padding(.vertical, 3)
            Text(copied.map { "Copied PID \($0)" } ?? "Click an app to copy its PID, right-click for more")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(10)
        .frame(width: 260)
    }

    private static let pidWidth: CGFloat = 44
    private static let valueWidth: CGFloat = 52

    private func row(_ app: ProcessUsage) -> some View {
        let highlighted = hovered == app.id
        return Button {
            copy(app.pid)
        } label: {
            HStack(spacing: 6) {
                AppIcon(image: icons.icon(for: app.path))
                Text(app.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(app.pid > 0 ? String(app.pid) : "—")
                    .foregroundStyle(highlighted ? Color.white.opacity(0.8) : Color.secondary)
                    .frame(width: Self.pidWidth, alignment: .trailing)
                Text(value(app))
                    .foregroundStyle(highlighted ? Color.white : Color.secondary)
                    .frame(minWidth: Self.valueWidth, alignment: .trailing)
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(highlighted ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(app.pid <= 0)
        .contextMenu {
            if app.pid > 0 {
                AppContextMenu(app: app) { copy(app.pid) }
            }
        }
        .onHover { inside in
            if inside {
                hovered = app.id
            } else if hovered == app.id {
                hovered = nil
            }
        }
        .help(details(app))
        .accessibilityLabel("\(app.name), \(value(app)), process ID \(app.pid)")
        .accessibilityHint("Copies the process ID")
    }

    private func details(_ app: ProcessUsage) -> String {
        let processes = app.processCount == 1 ? "1 process" : "\(app.processCount) processes"
        return [app.path, processes].compactMap { $0 }.joined(separator: "\n")
    }

    private func copy(_ pid: pid_t) {
        guard pid > 0 else { return }
        AppActions.copy(String(pid))
        copied = pid
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copied == pid { copied = nil }
        }
    }
}

/// A 14 pt app icon, or empty space of the same size.
private struct AppIcon: View {
    var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

/// Caches Finder icons by path. Owned by the popover model, so it is released when the popover closes.
@MainActor
final class IconCache {
    private var icons: [String: NSImage] = [:]
    private lazy var executableIcon = NSWorkspace.shared.icon(for: .unixExecutable)

    func icon(for path: String?) -> NSImage {
        guard let path else { return executableIcon }
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}
