import AppKit
import MonitorCore
import SwiftUI
import XCTest

@testable import MonitorUI

// DESIGN PROTOTYPE ONLY (never merged): renders the options for showing more top apps
// and acting on one of them, so they can be compared as real SwiftUI renders.

private struct ProtoApp: Identifiable {
    var name: String
    var path: String
    var pid: Int
    var processes: Int
    var value: String
    var id: String { name }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: path) }
}

private let protoApps: [ProtoApp] = [
    ProtoApp(name: "Safari", path: "/Applications/Safari.app", pid: 1279, processes: 14, value: "38%"),
    ProtoApp(name: "Photos", path: "/System/Applications/Photos.app", pid: 4021, processes: 3, value: "12%"),
    ProtoApp(name: "Music", path: "/System/Applications/Music.app", pid: 1104, processes: 2, value: "6.4%"),
    ProtoApp(name: "Mail", path: "/System/Applications/Mail.app", pid: 990, processes: 4, value: "2.1%"),
    ProtoApp(name: "Notes", path: "/System/Applications/Notes.app", pid: 1146, processes: 1, value: "0.8%"),
    ProtoApp(name: "Maps", path: "/System/Applications/Maps.app", pid: 2211, processes: 2, value: "0.5%"),
    ProtoApp(name: "Preview", path: "/System/Applications/Preview.app", pid: 3120, processes: 1, value: "0.3%"),
    ProtoApp(name: "Calendar", path: "/System/Applications/Calendar.app", pid: 1288, processes: 1, value: "0.1%"),
]

private let memApps: [ProtoApp] = [
    ProtoApp(name: "Safari", path: "/Applications/Safari.app", pid: 1279, processes: 14, value: "2.4 GB"),
    ProtoApp(name: "Photos", path: "/System/Applications/Photos.app", pid: 4021, processes: 3, value: "1.1 GB"),
    ProtoApp(name: "Mail", path: "/System/Applications/Mail.app", pid: 990, processes: 4, value: "640 MB"),
    ProtoApp(name: "Music", path: "/System/Applications/Music.app", pid: 1104, processes: 2, value: "410 MB"),
    ProtoApp(name: "Notes", path: "/System/Applications/Notes.app", pid: 1146, processes: 1, value: "220 MB"),
]

private struct ProtoRow: View {
    var app: ProtoApp
    var highlighted = false
    var showPID = false

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 14, height: 14)
            Text(app.name).lineLimit(1)
            Spacer(minLength: 4)
            if showPID {
                Text("\(app.pid)").monospacedDigit().foregroundStyle(.tertiary).frame(width: 40, alignment: .trailing)
            }
            Text(app.value).monospacedDigit().foregroundStyle(highlighted ? Color.white : Color.secondary)
                .frame(minWidth: 38, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(highlighted ? Color.accentColor : Color.clear))
    }
}

/// A metric card like the real one, with N apps and an optional disclosure control.
private struct ProtoCard: View {
    var symbol: String
    var title: String
    var reading: Reading
    var caption: String
    var apps: [ProtoApp]
    var disclosure: Bool? = nil  // nil: no control, false: collapsed, true: expanded
    var highlightIndex: Int? = nil
    var values: [Float]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                SymbolBadge(symbol: symbol, level: .ok)
                Text(title).font(.callout.weight(.medium))
                Spacer(minLength: 0)
                if let disclosure {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(disclosure ? 180 : 0))
                }
            }
            ValueText(reading: reading)
            Text(caption).font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            VStack(spacing: 2) {
                ForEach(Array(apps.enumerated()), id: \.offset) { i, app in
                    ProtoRow(app: app, highlighted: highlightIndex == i)
                        .padding(.horizontal, -4)
                }
            }
            Spacer(minLength: 0)
            Sparkline(values: values, maxValue: 1, color: .accentColor).frame(height: 22)
        }
        .modifier(ModuleBackground(level: .ok))
    }
}

/// Imitates an NSMenu, since a real one can't be captured in a test.
private struct ProtoMenu: View {
    var app: ProtoApp

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(app.name) · PID \(app.pid) · \(app.processes) processes")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
            item("Copy PID", "doc.on.doc", selected: true)
            item("Copy Path", nil)
            Divider().padding(.vertical, 4).padding(.horizontal, 10)
            item("Show in Finder", nil)
            item("Open Activity Monitor", nil)
            Divider().padding(.vertical, 4).padding(.horizontal, 10)
            item("Quit \(app.name)", nil)
            item("Force Quit \(app.name)…", nil)
        }
        .padding(5)
        .frame(width: 236)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
    }

    private func item(_ title: String, _ symbol: String?, selected: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
        }
        .font(.system(size: 13))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor : Color.clear))
    }
}

/// Imitates a small NSPopover attached under the top app line.
private struct ProtoPopover: View {
    var apps: [ProtoApp]
    var title: String

    var body: some View {
        VStack(spacing: 0) {
            Triangle().fill(Color(nsColor: .controlBackgroundColor)).frame(width: 18, height: 9)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.caption.weight(.semibold))
                    Spacer()
                    Text("PID").font(.caption2).foregroundStyle(.tertiary).frame(width: 40, alignment: .trailing)
                    Text("CPU").font(.caption2).foregroundStyle(.tertiary).frame(minWidth: 38, alignment: .trailing)
                }
                .padding(.horizontal, 4)
                ForEach(Array(apps.prefix(5).enumerated()), id: \.offset) { _, app in
                    ProtoRow(app: app, showPID: true)
                }
                Divider().padding(.vertical, 2)
                Text("Click an app for Copy PID, Quit, Force Quit").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(10)
            .frame(width: 250)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Control Center-style detail page that replaces the popover's content.
private struct ProtoDetail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                SymbolBadge(symbol: "cpu", level: .ok)
                Text("CPU").font(.headline)
                Spacer()
                Text("14 cores · 55 °C").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                ValueText(reading: Reading(value: "21", unit: "%"), size: 26)
                Sparkline(values: SampleData.wave(30, base: 0.21, amplitude: 0.08, seed: 3), maxValue: 1)
                    .frame(height: 44)
            }
            .modifier(ModuleBackground(level: .ok))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Apps").font(.caption.weight(.semibold))
                    Spacer()
                    Text("PID").font(.caption2).foregroundStyle(.tertiary).frame(width: 40, alignment: .trailing)
                    Text("CPU").font(.caption2).foregroundStyle(.tertiary).frame(minWidth: 38, alignment: .trailing)
                }
                .padding(.horizontal, 4).padding(.bottom, 2)
                ForEach(Array(protoApps.enumerated()), id: \.offset) { i, app in
                    ProtoRow(app: app, highlighted: i == 1, showPID: true)
                }
            }
            .modifier(ModuleBackground(level: .ok))
        }
        .padding(PopoverLayout.padding)
        .frame(width: PopoverLayout.width)
    }
}

@MainActor
final class TopAppsDesignTests: XCTestCase {
    func testRenderDesignOptions() throws {
        guard let dir = ProcessInfo.processInfo.environment["PREVIEW_DIR"] else {
            throw XCTSkip("Set PREVIEW_DIR to render previews")
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("design")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let cpuWave = SampleData.wave(30, base: 0.21, amplitude: 0.08, seed: 3)
        let memWave = SampleData.wave(30, base: 0.56, amplitude: 0.01, seed: 1)
        func cpu(_ n: Int, _ disclosure: Bool?, highlight: Int? = nil) -> ProtoCard {
            ProtoCard(
                symbol: "cpu", title: "CPU", reading: Reading(value: "21", unit: "%"), caption: "14 cores · 55 °C",
                apps: Array(protoApps.prefix(n)), disclosure: disclosure, highlightIndex: highlight, values: cpuWave)
        }
        func mem(_ n: Int, _ disclosure: Bool?) -> ProtoCard {
            ProtoCard(
                symbol: "memorychip", title: "Memory", reading: Reading(value: "20.3", unit: "GB"),
                caption: "of 36.0 GB · pressure normal", apps: Array(memApps.prefix(n)), disclosure: disclosure,
                values: memWave)
        }
        func row(_ a: some View, _ b: some View) -> some View {
            HStack(alignment: .top, spacing: PopoverLayout.spacing) { a; b }
                .fixedSize(horizontal: false, vertical: true)
                .padding(PopoverLayout.padding)
                .frame(width: PopoverLayout.width)
        }

        let appearance = NSAppearance.Name.darkAqua
        // Today.
        try render(row(cpu(1, nil), mem(1, nil)), appearance).write(to: url.appendingPathComponent("0-today.png"))
        // A: expand in place, only the row that was clicked grows.
        try render(
            VStack(spacing: 0) {
                row(cpu(1, false), mem(1, false))
                row(cpu(5, true), mem(1, false))
            }, appearance
        ).write(to: url.appendingPathComponent("a-inline.png"))
        // B: a small popover under the top app line.
        try render(
            VStack(alignment: .leading, spacing: -6) {
                row(cpu(1, nil, highlight: 0), mem(1, nil))
                ProtoPopover(apps: protoApps, title: "Top apps by CPU").padding(.leading, 14).padding(.bottom, 16)
            }, appearance
        ).write(to: url.appendingPathComponent("b-popover.png"))
        // C: detail page.
        try render(ProtoDetail(), appearance).write(to: url.appendingPathComponent("c-detail.png"))
        // Actions menu on an app.
        try render(
            ZStack(alignment: .topLeading) {
                row(cpu(5, true, highlight: 1), mem(1, false))
                ProtoMenu(app: protoApps[1]).padding(.leading, 70).padding(.top, 150)
            }
            .frame(height: 430, alignment: .top), appearance
        ).write(to: url.appendingPathComponent("menu.png"))
    }

    private func render(_ content: some View, _ appearance: NSAppearance.Name) throws -> Data {
        let root = content
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(24)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let size = host.bounds.size
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { throw XCTSkip("Could not allocate bitmap") }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw XCTSkip("PNG") }
        return png
    }
}
