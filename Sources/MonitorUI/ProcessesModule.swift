import AppKit
import MonitorCore
import SwiftUI
import UniformTypeIdentifiers

/// The apps using the most CPU and memory, side by side. Rows keep their height while data
/// is still arriving, so the popover never changes size.
@MainActor
struct ProcessesModule: View {
    var processes: TopProcesses?
    var icons: IconCache

    static let rowCount = 3

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            column(title: "Most CPU", items: processes?.byCPU ?? []) { Format.processCPU($0.cpu) }
            Divider().opacity(0.5)
            column(title: "Most Memory", items: processes?.byMemory ?? []) { Format.processMemory($0.memoryBytes) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .modifier(ModuleBackground(level: .ok))
    }

    private func column(
        title: String, items: [ProcessUsage], value: @escaping (ProcessUsage) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout.weight(.medium))
            ForEach(0..<Self.rowCount, id: \.self) { index in
                if index < items.count {
                    let item = items[index]
                    ProcessRow(name: item.name, value: value(item), icon: icons.icon(for: item.path))
                } else {
                    ProcessRow(name: "", value: "", icon: nil).hidden()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProcessRow: View {
    var name: String
    var value: String
    var icon: NSImage?

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Color.clear
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
            Text(name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
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
