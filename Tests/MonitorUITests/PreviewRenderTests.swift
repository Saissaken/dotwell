import AppKit
import MonitorCore
import SwiftUI
import XCTest

@testable import MonitorUI

/// Renders the popover with sample data to PNG files.
/// Runs only when `PREVIEW_DIR` is set (CI sets it and uploads the images).
@MainActor
final class PreviewRenderTests: XCTestCase {
    func testRenderPreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["PREVIEW_DIR"] else {
            throw XCTSkip("Set PREVIEW_DIR to render previews")
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let locale = Format.temperatureFormatter.locale
        Format.temperatureFormatter.locale = Locale(identifier: "en_GB")  // °C in the README screenshots
        defer { Format.temperatureFormatter.locale = locale }

        let cases: [(String, Snapshot)] = [("healthy", SampleData.healthy), ("issues", SampleData.issues)]
        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        for (name, snapshot) in cases {
            for (mode, appearance) in appearances {
                let model = PopoverModel(snapshot: snapshot)
                model.addresses = SampleData.addresses
                let data = try render(
                    PopoverView(model: model, settings: AppSettings(defaults: nil)), appearance: appearance)
                try data.write(to: url.appendingPathComponent("popover-\(name)-\(mode).png"))
            }
        }
        for (mode, appearance) in appearances {
            for tab in SettingsTab.allCases {
                let data = try renderSettings(tab: tab, appearance: appearance)
                try data.write(to: url.appendingPathComponent("settings-\(tab.rawValue)-\(mode).png"))
            }
        }
        // The Ping module with the route's router list open.
        for (mode, appearance) in appearances {
            let issues = SampleData.issues
            let module = PingModule(snapshot: issues, level: issues.level(.ping), pathExpanded: true)
                .padding(12)
                .frame(width: 360)
            let data = try render(module, appearance: appearance)
            try data.write(to: url.appendingPathComponent("ping-path-\(mode).png"))
        }
        // The detail that opens from a ping row.
        for (mode, appearance) in appearances {
            let snap = SampleData.healthy
            let context = PingRowContext(thresholds: snap.thresholds, pathIndex: nil, actions: nil)
            let detail = PingDetail(target: snap.ping[4], name: snap.ping[4].target.name, context: context)
            let data = try render(detail, appearance: appearance)
            try data.write(to: url.appendingPathComponent("ping-detail-\(mode).png"))
        }
        // The list that opens from a top app line.
        for (mode, appearance) in appearances {
            let list = TopAppsList(
                title: "Top Apps by CPU", column: "CPU", apps: SampleData.healthy.topApps?.byCPU ?? [],
                value: { Format.processCPU($0.cpu) }, icons: IconCache())
            let data = try render(list, appearance: appearance)
            try data.write(to: url.appendingPathComponent("top-apps-\(mode).png"))
        }
    }

    /// Renders the real Settings window, title bar and toolbar included, on one tab.
    private func renderSettings(tab: SettingsTab, appearance: NSAppearance.Name) throws -> Data {
        let updates = UpdateSettings(
            UpdateSettings.Backend(
                automaticallyChecks: { true }, setAutomaticallyChecks: { _ in },
                automaticallyDownloads: { true }, setAutomaticallyDownloads: { _ in },
                lastCheck: { Date().addingTimeInterval(-2 * 3600) }, checkNow: {}))
        let model = SettingsModel(settings: AppSettings(defaults: nil), launchAtLogin: true, updates: updates)
        model.version = "0.4.0 (14)"
        let tabs = SettingsTabViewController(model: model)
        tabs.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
        let window = tabs.makeWindow()
        window.appearance = NSAppearance(named: appearance)
        window.setFrameOrigin(NSPoint(x: 100, y: 100))
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        defer { window.orderOut(nil) }
        // The theme frame is the window's root view: it draws the title bar and toolbar too.
        guard let frame = window.contentView?.superview else { throw XCTSkip("No window frame view") }
        return try pngData(of: frame)
    }

    private func render(_ content: some View, appearance: NSAppearance.Name) throws -> Data {
        let root =
            content
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(24)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return try pngData(of: host)
    }

    private func pngData(of view: NSView) throws -> Data {
        let size = view.bounds.size
        let scale = 2
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { throw XCTSkip("Could not allocate bitmap") }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw XCTSkip("Could not encode PNG")
        }
        return png
    }
}

/// Deterministic sample snapshots for previews and screenshots.
enum SampleData {
    static func wave(_ count: Int, base: Float, amplitude: Float, seed: Float = 0) -> [Float] {
        (0..<count).map { i in
            let x = Float(i) + seed
            return max(0, base + amplitude * (sin(x * 0.45) * 0.6 + sin(x * 1.3) * 0.4))
        }
    }

    static var healthy: Snapshot {
        var s = Snapshot()
        s.cpu = 0.18
        s.cpuTemperature = 46
        s.fanRPM = 0
        s.memory = MemorySample(usedBytes: 11_400_000_000, totalBytes: 17_179_869_184, pressure: .normal)
        s.disk = DiskSpace(availableBytes: 212_000_000_000, totalBytes: 494_000_000_000)
        s.diskReadBytesPerSec = 2_400_000
        s.diskWriteBytesPerSec = 600_000
        s.power = PowerSample(source: .battery, watts: 7.8, isCharging: false, batteryCelsius: 31)
        s.gpu = GPUSample(utilization: 0.12, coreCount: 10, watts: 0.9, temperature: 41)
        s.networkDownBitsPerSec = 312_000_000
        s.networkUpBitsPerSec = 24_000_000
        s.ping = pingTargets(primaryMs: 14, primaryLoss: 0)
        s.levels = [.ping: .ok, .cpu: .ok, .memory: .ok, .disk: .ok, .power: .ok, .thermal: .ok]
        s.history = [
            SeriesKey.ping(PingTarget.defaultPrimaryIndex): wave(30, base: 14, amplitude: 3),
            SeriesKey.cpu: wave(30, base: 0.18, amplitude: 0.08, seed: 3),
            SeriesKey.gpu: wave(30, base: 0.12, amplitude: 0.05, seed: 6),
            SeriesKey.memory: wave(30, base: 0.66, amplitude: 0.01, seed: 1),
            SeriesKey.power: wave(30, base: 7.8, amplitude: 2, seed: 5),
            SeriesKey.diskRead: wave(30, base: 2_000_000, amplitude: 1_500_000, seed: 2),
            SeriesKey.netDown: wave(30, base: 200e6, amplitude: 120e6, seed: 4),
            SeriesKey.netUp: wave(30, base: 20e6, amplitude: 10e6, seed: 7),
        ]
        s.topApps = TopApps(
            byCPU: [
                app("Safari", cpu: 0.214), app("Photos", cpu: 0.12), app("Music", cpu: 0.064),
                app("Mail", cpu: 0.021), app("Notes", cpu: 0.008),
            ],
            byMemory: [app("Safari", memory: 2.4), app("Photos", memory: 1.1), app("Mail", memory: 0.62)],
            byDisk: [app("Photos", disk: 1_800_000)], byPower: [app("Safari", watts: 2.1)],
            byGPU: [app("Safari", gpu: 0.06), app("Photos", gpu: 0.02)])
        s.path = path(ispMs: 9, internetMs: 12, serverMs: 14, serverLost: 0)
        return s
    }

    /// Documentation-range addresses (RFC 5737, RFC 3849), never a real Mac's.
    static let addresses = NetworkAddresses(
        local: LocalAddress(interface: "en0", kind: .wifi, ipv4: "192.168.1.42"),
        publicAddresses: PublicAddresses(ipv4: "203.0.113.24", ipv6: "2001:db8:85a3::8a2e:370:7334"))

    static var issues: Snapshot {
        var s = healthy
        s.cpu = 0.91
        s.cpuTemperature = 97
        s.thermal = .serious
        s.levels[.thermal] = .warning
        s.ping = pingTargets(primaryMs: 96, primaryLoss: 0.03)
        s.levels[.ping] = .warning
        s.levels[.cpu] = .warning
        var pingHistory = wave(30, base: 40, amplitude: 10)
        for i in 18..<30 { pingHistory[i] += Float(i - 16) * 6 }
        pingHistory[24] = PingStats.lost
        s.history[SeriesKey.ping(PingTarget.defaultPrimaryIndex)] = pingHistory
        s.history[SeriesKey.cpu] = wave(30, base: 0.85, amplitude: 0.08, seed: 3)
        s.topApps?.byCPU.insert(app("Photos", cpu: 2.864), at: 0)
        s.topApps?.byCPU.removeAll { $0.name == "Photos" && $0.cpu < 1 }
        s.path = path(ispMs: 72, internetMs: 81, serverMs: 96, serverLost: 1)
        return s
    }

    /// A typical home connection: router, carrier-grade NAT and two ISP routers, a transit router, Cloudflare.
    private static func path(ispMs: Float, internetMs: Float, serverMs: Float, serverLost: Int) -> PathTrace {
        func hop(_ ttl: Int, _ address: String?, _ hostname: String?, _ ms: Float, lost: Int = 0) -> TraceHop {
            var samples = address == nil ? [] : wave(10, base: ms, amplitude: ms * 0.06, seed: Float(ttl))
            for i in 0..<lost { samples[2 + i * 4] = PingStats.lost }
            return TraceHop(
                ttl: ttl, address: address, hostname: hostname, stats: PingStats.compute(samples),
                isDestination: ttl == 7)
        }
        return PathTrace(
            hops: [
                hop(1, "192.168.1.1", nil, 3.1),
                hop(2, "100.64.0.1", nil, ispMs * 0.8),
                hop(3, "200.51.240.17", "ae3.core1.andesnet.com.ar", ispMs * 0.95),
                hop(4, nil, nil, 0),
                hop(5, "181.30.1.5", "ae0.core2.andesnet.com.ar", ispMs),
                hop(6, "195.22.220.57", "et-1-1.transit.example.net", internetMs),
                hop(7, "1.1.1.1", "one.one.one.one", serverMs, lost: serverLost),
            ], rounds: 12)
    }

    /// A system app that exists on every Mac, so the screenshot shows its real icon.
    private static func app(
        _ name: String, cpu: Float = 0, memory gigabytes: Double = 0, disk: Double = 0, watts: Double = 0,
        gpu: Float = 0
    ) -> ProcessUsage {
        let path = name == "Safari" ? "/Applications/Safari.app" : "/System/Applications/\(name).app"
        let bytes = UInt64(gigabytes * 1_073_741_824)
        let pids = ["Safari": 1279, "Photos": 4021, "Music": 1104, "Mail": 990, "Notes": 1146]
        return ProcessUsage(
            id: path, name: name, path: path, cpu: cpu, memoryBytes: bytes, diskBytesPerSec: disk, watts: watts,
            pid: pid_t(pids[name] ?? 500), processCount: name == "Safari" ? 14 : 2, gpu: gpu)
    }

    private static func pingTargets(primaryMs: Float, primaryLoss: Float) -> [PingTargetState] {
        let samples: [Float] = [3.1, 9.4, 3.1, primaryMs, 34, 142]
        let addresses: [String?] = ["192.168.1.1", "181.30.128.1", "192.168.1.1", "1.1.1.1", "198.51.100.18", nil]
        return PingTarget.defaults.enumerated().map { index, target in
            var values = wave(10, base: samples[index], amplitude: samples[index] * 0.08, seed: Float(index))
            values[9] = samples[index]
            if index == PingTarget.defaultPrimaryIndex && primaryLoss > 0 { values[3] = PingStats.lost }
            let interval = target.method == .icmp ? 1 : 5
            var minute = wave(60 / interval, base: samples[index], amplitude: samples[index] * 0.1, seed: Float(index))
            if index == 4 { minute[7] = PingStats.lost }
            var state = PingTargetState(
                index: index, target: target, stats: PingStats.compute(values),
                isPrimary: index == PingTarget.defaultPrimaryIndex, address: addresses[index],
                probeIntervalMilliseconds: interval * 1000)
            state.lastMinute = minute
            state.lastMinuteChart = minute.flatMap { Array(repeating: $0, count: 2 * interval) }  // half-second slots
            return state
        }
    }
}
