import AppKit
import MonitorCore
import SwiftUI
import XCTest

@testable import MonitorUI

// Design exploration only: static mockups of three Settings layouts, rendered with real AppKit
// windows and SwiftUI controls. Nothing here is wired to AppSettings. Not meant to merge.

// MARK: - Shared building blocks (System Settings look)

private struct Section2<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 2)
            }
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

private struct Row<Control: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct RowDivider: View {
    var body: some View { Divider().padding(.horizontal, 10) }
}

private struct OnSwitch: View {
    var on = true
    var body: some View {
        Toggle("", isOn: .constant(on)).toggleStyle(.switch).controlSize(.small).labelsHidden()
    }
}

private struct MenuPicker: View {
    var selected: String
    var options: [String]
    var body: some View {
        Picker("", selection: .constant(selected)) {
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }
}

private struct NumberBox: View {
    var value: String
    var unit: String
    var dot: Color?
    var body: some View {
        HStack(spacing: 4) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            TextField("", text: .constant(value))
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .labelsHidden()
            Stepper("", value: .constant(0), in: 0...1).labelsHidden()
            Text(unit).foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
        }
    }
}

/// A drawn macOS help tag, since hover tooltips can't be captured off screen.
private struct FakeTooltip: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color(nsColor: .labelColor))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: 260, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.15)))
    }
}

private struct PointerCursor: View {
    var body: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 16))
            .foregroundStyle(.black)
            .shadow(color: .white, radius: 0.5)
    }
}

private struct WidgetHeader: View {
    var symbol: String
    var title: String
    var detail: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                OnSwitch()
                Text("Show in panel").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct WebsiteLink: View {
    var body: some View {
        Link(destination: URL(fileURLWithPath: "/")) {
            HStack(spacing: 3) {
                Text("saissaken.github.io/dotwell")
                Image(systemName: "arrow.up.right.square")
            }
        }
    }
}

private let openIntervals = ["Every 0.5 seconds", "Every second", "Every 2 seconds"]
private let closedIntervals = [
    "Every second", "Every 2 seconds", "Every 5 seconds (recommended)", "Every 10 seconds", "Every 30 seconds",
]

// MARK: - Shared pages (proposals A and B)

private struct GeneralPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Section2(title: nil) {
                Row(title: "Open Dotwell at login") { OnSwitch() }
            }
            Section2(
                title: "Update readings",
                footer:
                    "Charts and alerts adapt to the interval. The closed setting matters most for battery, "
                    + "because it runs all day."
            ) {
                Row(
                    title: "While the panel is open",
                    detail: "Only while you're looking at it, so faster is fine."
                ) {
                    MenuPicker(selected: "Every second", options: openIntervals)
                }
                RowDivider()
                Row(
                    title: "While the panel is closed",
                    detail: "Keeps the menu bar light current. Very low energy use; "
                        + "the light reacts to a problem within about 5 seconds."
                ) {
                    MenuPicker(selected: "Every 5 seconds (recommended)", options: closedIntervals)
                }
            }
            Section2(title: nil) {
                Row(title: "Website", detail: "News, help and the source code.") { WebsiteLink() }
            }
        }
    }
}

private struct CPUPage: View {
    var showsTooltip = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WidgetHeader(
                symbol: "cpu", title: "CPU",
                detail: "How busy the processor is, its temperature, and whether macOS is slowing it down.")
            Section2(title: "Card") {
                Row(
                    title: "Show the busiest app",
                    detail: "Names the app using the most CPU while the panel is open."
                ) { OnSwitch() }
                .overlay(alignment: .topLeading) {
                    if showsTooltip {
                        ZStack(alignment: .topLeading) {
                            PointerCursor().offset(x: 120, y: 6)
                            FakeTooltip(
                                text: "Shows the name and icon of the app using the most CPU right now. "
                                    + "Dotwell only checks per-app use while the panel is open."
                            )
                            .offset(x: 130, y: 26)
                        }
                    }
                }
                .zIndex(1)
                RowDivider()
                Row(title: "Show temperature", detail: "Read from the Mac's sensors. Not every Mac has them.") {
                    OnSwitch()
                }
            }
            .zIndex(1)
            Section2(
                title: "Slowing down to cool",
                footer: "Replaces the old Thermal card. macOS slows the Mac only when it gets very hot, "
                    + "so most days you'll never see it."
            ) {
                Row(
                    title: "Warn when macOS slows the Mac down",
                    detail: "Adds a \"Slowed down to cool\" line to this card and turns the light yellow or red."
                ) { OnSwitch() }
            }
            Section2(title: "Alert", footer: "Yellow after 30 seconds above the limit, red after a minute.") {
                Row(title: "Alert when the CPU stays busy") { OnSwitch() }
                RowDivider()
                Row(title: "Yellow above") { NumberBox(value: "80", unit: "%", dot: .orange) }
                RowDivider()
                Row(title: "Red above") { NumberBox(value: "95", unit: "%", dot: .red) }
            }
        }
    }
}

private struct NetworkPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WidgetHeader(
                symbol: "arrow.up.arrow.down", title: "Network",
                detail: "Download and upload speed, and this Mac's addresses.")
            Section2(title: "Speed") {
                Row(
                    title: "Show speed in",
                    detail: "Mbps matches internet plans and speed tests. MB/s matches downloads in Finder."
                ) {
                    MenuPicker(
                        selected: "Mbps", options: ["Mbps", "MB/s"])
                }
            }
            Section2(title: "IP addresses") {
                Row(
                    title: "Show local and public IP addresses",
                    detail: "Turn off before sharing your screen. When off, Dotwell never looks up "
                        + "your public address."
                ) { OnSwitch() }
            }
            Section2(title: "Alert", footer: nil) {
                Row(
                    title: "No alert for speed",
                    detail: "A slow connection already shows up in Ping, which measures it reliably."
                ) { EmptyView() }
            }
        }
    }
}

private struct PingPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WidgetHeader(
                symbol: "network", title: "Ping",
                detail: "How long your router, your provider and the internet take to answer.")
            Section2(title: "Hosts") {
                Row(
                    title: "Router and ISP",
                    detail: "Found on their own: your Wi-Fi or Ethernet router, then your provider's first router."
                ) { Text("Automatic").foregroundStyle(.secondary) }
                RowDivider()
                Row(title: "Internet", detail: "Answered by the closest server of a global network.") {
                    MenuPicker(selected: "Cloudflare (1.1.1.1)", options: ["Cloudflare (1.1.1.1)"])
                }
                RowDivider()
                RegionRow(index: 1, name: "AWS · São Paulo", ms: "38 ms")
                RowDivider()
                RegionRow(index: 2, name: "AWS · Virginia", ms: "142 ms")
                RowDivider()
                Row(title: "DNS lookup", detail: "Time your Mac's DNS server takes to answer a name.") { OnSwitch() }
            }
            Section2(
                title: "Main host",
                footer: "The main host is shown big at the top of the card, traced router by router, "
                    + "and is the one whose alert colors the menu bar light."
            ) {
                Row(title: "Main host") {
                    MenuPicker(selected: "Internet (Cloudflare)", options: ["Internet (Cloudflare)"])
                }
            }
            Section2(title: "Alert", footer: "Applies to the main host. Yellow or red after 3 seconds.") {
                Row(title: "Alert when ping is slow or drops replies") { OnSwitch() }
                RowDivider()
                Row(title: "Latency") {
                    HStack(spacing: 10) {
                        NumberBox(value: "80", unit: "ms", dot: .orange)
                        NumberBox(value: "200", unit: "ms", dot: .red)
                    }
                }
                RowDivider()
                Row(title: "Packet loss") {
                    HStack(spacing: 10) {
                        NumberBox(value: "2", unit: "%", dot: .orange)
                        NumberBox(value: "10", unit: "%", dot: .red)
                    }
                }
            }
        }
    }
}

private struct RegionRow: View {
    var index: Int
    var name: String
    var ms: String
    var body: some View {
        Row(
            title: "Region \(index)",
            detail: index == 2 ? "Clouds ignore ping, so Dotwell times a connection instead." : nil
        ) {
            HStack(spacing: 8) {
                Text(name)
                Text(ms).monospacedDigit().foregroundStyle(.secondary)
                Button("Choose…") {}
            }
        }
    }
}

/// The region chooser with live latency, measured only while it's open.
private struct RegionChooser: View {
    struct Option: Identifiable {
        var city: String
        var code: String
        var ms: Int?
        var id: String { code }
    }
    let options: [Option] = [
        .init(city: "São Paulo", code: "sa-east-1", ms: 38),
        .init(city: "Ohio", code: "us-east-2", ms: 131),
        .init(city: "Virginia", code: "us-east-1", ms: 142),
        .init(city: "Mexico", code: "mx-central-1", ms: 149),
        .init(city: "Oregon", code: "us-west-2", ms: 188),
        .init(city: "California", code: "us-west-1", ms: 192),
        .init(city: "Ireland", code: "eu-west-1", ms: 219),
        .init(city: "Frankfurt", code: "eu-central-1", ms: 236),
        .init(city: "Tokyo", code: "ap-northeast-1", ms: nil),
        .init(city: "Sydney", code: "ap-southeast-2", ms: nil),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Region 1").font(.system(size: 13, weight: .semibold))
            Picker("", selection: .constant("AWS")) {
                Text("AWS").tag("AWS")
                Text("Google Cloud").tag("GCP")
                Text("Azure").tag("Azure")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .opacity(index == 0 ? 1 : 0)
                        Text(option.city)
                        Text(option.code).foregroundStyle(.secondary).font(.system(size: 11))
                        Spacer()
                        if let ms = option.ms {
                            Circle().fill(dotColor(ms)).frame(width: 7, height: 7)
                            Text("\(ms) ms").monospacedDigit().frame(width: 56, alignment: .trailing)
                        } else {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                            Text("measuring").foregroundStyle(.secondary).font(.system(size: 11))
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(index == 0 ? Color.accentColor.opacity(0.15) : Color.clear)
                    if index < options.count - 1 { RowDivider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
            Text(
                "Measured from this Mac right now, fastest first. Dotwell measures only while this "
                    + "window is open."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") {}
                Button("Choose") {}.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func dotColor(_ ms: Int) -> Color { ms < 80 ? .green : ms < 200 ? .orange : .red }
}

// MARK: - Proposal A: sidebar, one page per widget

private struct SidebarMock<Detail: View>: View {
    var selected: String
    @ViewBuilder var detail: Detail

    private let widgets: [(String, String)] = [
        ("network", "Ping"), ("cpu", "CPU"), ("memorychip", "Memory"), ("arrow.up.arrow.down", "Network"),
        ("internaldrive", "Disk"), ("battery.75percent", "Battery"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Spacer().frame(height: 40)
                item("gearshape", "General")
                Text("Widgets · drag to reorder the panel")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                    .padding(.leading, 10)
                    .padding(.bottom, 2)
                ForEach(widgets, id: \.1) { item($0.0, $0.1) }
                Divider().padding(.vertical, 8).padding(.horizontal, 10)
                item("arrow.triangle.2.circlepath", "Updates")
                item("info.circle", "About")
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(width: 210)
            .frame(maxHeight: .infinity)
            .background(Color.primary.opacity(0.05))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(selected).font(.system(size: 15, weight: .semibold)).padding(.bottom, 14)
                detail
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 22)
            .frame(width: 500)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func item(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(title == selected ? Color.white.opacity(0.25) : .gray))
            Text(title).foregroundStyle(title == selected ? Color.white : Color.primary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(title == selected ? Color.accentColor : .clear))
    }
}

// MARK: - Proposal B: tabs, widgets as expandable cards

private struct ExpandableWidgetsTab: View {
    private let rows: [(String, String, String)] = [
        ("network", "Ping", "Router, provider, internet and two cloud regions"),
        ("cpu", "CPU", "Usage, temperature and slow-down warnings"),
        ("memorychip", "Memory", "Used memory and memory pressure"),
        ("arrow.up.arrow.down", "Network", "Speed and IP addresses"),
        ("internaldrive", "Disk", "Free space and read/write speed"),
        ("battery.75percent", "Battery", "Power draw. Only on Macs with a battery"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Click a card to change it. Drag to change the order in the panel.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.1) { index, row in
                    header(row, expanded: row.1 == "CPU")
                    if row.1 == "CPU" { cpuBody }
                    if index < rows.count - 1 { RowDivider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        }
        .padding(20)
        .frame(width: 560)
    }

    private func header(_ row: (String, String, String), expanded: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .foregroundStyle(.secondary)
            SymbolBadge(symbol: row.0, level: .ok)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.1)
                Text(row.2).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            OnSwitch()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var cpuBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Row(title: "Show the busiest app", detail: "Names the app using the most CPU while the panel is open.") {
                OnSwitch()
            }
            Row(title: "Show temperature", detail: "Read from the Mac's sensors.") { OnSwitch() }
            Row(
                title: "Warn when macOS slows the Mac down to cool it",
                detail: "Replaces the Thermal card. Rare: only when the Mac is very hot."
            ) { OnSwitch() }
            Row(title: "Alert when busy for 30 s", detail: "Red after a minute.") {
                HStack(spacing: 10) {
                    NumberBox(value: "80", unit: "%", dot: .orange)
                    NumberBox(value: "95", unit: "%", dot: .red)
                }
            }
        }
        .padding(.leading, 56)
        .padding(.trailing, 4)
        .padding(.bottom, 6)
        .background(Color.primary.opacity(0.025))
    }
}

// MARK: - Proposal C: one toolbar tab per widget, classic columns

private struct ColumnsCPUTab: View {
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                label("Panel:")
                Toggle("Show the CPU card", isOn: .constant(true))
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show the busiest app", isOn: .constant(true))
                    note("The app using the most CPU, checked only while the panel is open.")
                    Toggle("Show temperature", isOn: .constant(true))
                }
            }
            spacer
            GridRow {
                label("Slowing down:")
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Warn when macOS slows the Mac down to cool it", isOn: .constant(true))
                    note("Replaces the Thermal card. Rare: only when the Mac is very hot.")
                }
            }
            spacer
            GridRow {
                label("Alert:")
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Alert when the CPU stays busy", isOn: .constant(true))
                    HStack(spacing: 10) {
                        NumberBox(value: "80", unit: "%", dot: .orange)
                        NumberBox(value: "95", unit: "%", dot: .red)
                    }
                    note("Yellow after 30 seconds above the limit, red after a minute.")
                }
            }
        }
        .padding(20)
        .frame(width: 600, alignment: .leading)
    }

    private var spacer: some View { GridRow { Spacer().frame(height: 6) } }
    private func label(_ text: String) -> some View { Text(text).gridColumnAlignment(.trailing).frame(width: 110, alignment: .trailing) }
    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 400, alignment: .leading)
    }
}

private struct ColumnsGeneralTab: View {
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                label("Startup:")
                Toggle("Open Dotwell at login", isOn: .constant(true))
            }
            GridRow { Spacer().frame(height: 6) }
            GridRow {
                label("Panel open:")
                VStack(alignment: .leading, spacing: 4) {
                    MenuPicker(selected: "Every second", options: openIntervals)
                    note("Only while you're looking at it, so faster is fine.")
                }
            }
            GridRow {
                label("Panel closed:")
                VStack(alignment: .leading, spacing: 4) {
                    MenuPicker(selected: "Every 5 seconds (recommended)", options: closedIntervals)
                    note("Runs all day to keep the menu bar light current. Very low energy use.")
                }
            }
            GridRow { Spacer().frame(height: 6) }
            GridRow {
                label("Card order:")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(["Ping", "CPU", "Memory", "Network", "Disk", "Battery"], id: \.self) { name in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Text(name)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                    }
                }
                .frame(width: 220)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            }
            GridRow { Spacer().frame(height: 6) }
            GridRow {
                label("Website:")
                WebsiteLink()
            }
        }
        .padding(20)
        .frame(width: 640, alignment: .leading)
    }

    private func label(_ text: String) -> some View { Text(text).gridColumnAlignment(.trailing).frame(width: 110, alignment: .trailing) }
    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 420, alignment: .leading)
    }
}

// MARK: - About

private struct AboutMock: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Dotwell").font(.system(size: 15, weight: .bold))
            Text("Version 0.6.0 (20)").font(.system(size: 11)).foregroundStyle(.secondary)
            WebsiteLink().font(.system(size: 11)).padding(.top, 4)
            Text("© 2026 Dotwell contributors. MIT License.").font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 280)
    }
}

// MARK: - Renderer

@MainActor
final class DesignMockupTests: XCTestCase {
    func testRenderDesignMockups() throws {
        guard let dir = ProcessInfo.processInfo.environment["PREVIEW_DIR"] else {
            throw XCTSkip("Set PREVIEW_DIR to render mockups")
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("design")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let modes: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

        for (mode, appearance) in modes {
            func save(_ data: Data, _ name: String) throws {
                try data.write(to: url.appendingPathComponent("\(name)-\(mode).png"))
            }
            // A
            try save(window(SidebarMock(selected: "General") { GeneralPage() }, appearance), "A1-general")
            try save(window(SidebarMock(selected: "CPU") { CPUPage(showsTooltip: true) }, appearance), "A2-cpu")
            try save(window(SidebarMock(selected: "Network") { NetworkPage() }, appearance), "A3-network")
            try save(window(SidebarMock(selected: "Ping") { PingPage() }, appearance), "A4-ping")
            try save(window(RegionChooser(), appearance), "region-chooser")
            try save(window(AboutMock(), appearance), "about")
            // B
            try save(
                tabs(
                    [
                        ("General", "gearshape", AnyView(GeneralPage().padding(20).frame(width: 560))),
                        ("Widgets", "square.grid.2x2", AnyView(ExpandableWidgetsTab())),
                        ("Ping", "network", AnyView(EmptyView())),
                        ("Updates", "arrow.triangle.2.circlepath", AnyView(EmptyView())),
                    ], selected: 1, appearance), "B1-widgets")
            try save(
                tabs(
                    [
                        ("General", "gearshape", AnyView(GeneralPage().padding(20).frame(width: 560))),
                        ("Widgets", "square.grid.2x2", AnyView(EmptyView())),
                        ("Ping", "network", AnyView(EmptyView())),
                        ("Updates", "arrow.triangle.2.circlepath", AnyView(EmptyView())),
                    ], selected: 0, appearance), "B2-general")
            // C
            let cTabs: [(String, String)] = [
                ("General", "gearshape"), ("Ping", "network"), ("CPU", "cpu"), ("Memory", "memorychip"),
                ("Network", "arrow.up.arrow.down"), ("Disk", "internaldrive"), ("Battery", "battery.75percent"),
                ("Updates", "arrow.triangle.2.circlepath"),
            ]
            func cItems(_ page: Int, _ view: AnyView) -> [(String, String, AnyView)] {
                cTabs.enumerated().map { i, t in (t.0, t.1, i == page ? view : AnyView(EmptyView())) }
            }
            try save(tabs(cItems(2, AnyView(ColumnsCPUTab())), selected: 2, appearance), "C1-cpu")
            try save(tabs(cItems(0, AnyView(ColumnsGeneralTab())), selected: 0, appearance), "C2-general")
        }
    }

    private func window(_ content: some View, _ appearance: NSAppearance.Name) throws -> Data {
        let host = NSHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.title = ""
        return try capture(window, appearance)
    }

    private func tabs(
        _ items: [(String, String, AnyView)], selected: Int, _ appearance: NSAppearance.Name
    ) throws -> Data {
        let controller = NSTabViewController()
        controller.tabStyle = .toolbar
        for (title, symbol, view) in items {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = .preferredContentSize
            host.title = title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            controller.addTabViewItem(item)
        }
        controller.selectedTabViewItemIndex = selected
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        return try capture(window, appearance)
    }

    private func capture(_ window: NSWindow, _ appearance: NSAppearance.Name) throws -> Data {
        window.appearance = NSAppearance(named: appearance)
        window.setFrameOrigin(NSPoint(x: 100, y: 100))
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        defer { window.orderOut(nil) }
        guard let frame = window.contentView?.superview else { throw XCTSkip("No window frame view") }
        let size = frame.bounds.size
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { throw XCTSkip("Could not allocate bitmap") }
        rep.size = size
        frame.cacheDisplay(in: frame.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw XCTSkip("No PNG") }
        return png
    }
}
