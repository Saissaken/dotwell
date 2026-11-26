import AppKit
import MonitorCore
import SwiftUI
import UniformTypeIdentifiers

/// One compact line inside a metric module: the app using the most of that resource.
/// With no app yet, the line keeps its height so the popover doesn't change size.
struct TopAppRow: View {
    var app: ProcessUsage?
    var value: String
    var icon: NSImage?

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Color.clear
                }
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
            Text(app?.name ?? " ")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .font(.caption)
        .opacity(app == nil ? 0 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.map { "Top app: \($0.name), \(value)" } ?? "")
        .help(app.map { "Using the most right now: \($0.name)" } ?? "")
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
