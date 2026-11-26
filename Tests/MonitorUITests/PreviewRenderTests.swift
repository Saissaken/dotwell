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
                let data = try render(snapshot: snapshot, appearance: appearance)
                try data.write(to: url.appendingPathComponent("popover-\(name)-\(mode).png"))
            }
        }
    }

    private func render(snapshot: Snapshot, appearance: NSAppearance.Name) throws -> Data {
        let model = PopoverModel(snapshot: snapshot, launchAtLogin: true)
        let root = PopoverView(model: model)
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

        let scale = 2
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { throw XCTSkip("Could not allocate bitmap") }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
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
        s.memory = MemorySample(usedBytes: 11_400_000_000, totalBytes: 17_179_869_184, pressure: .normal)
        s.disk = DiskSpace(availableBytes: 212_000_000_000, totalBytes: 494_000_000_000)
        s.diskReadBytesPerSec = 2_400_000
        s.diskWriteBytesPerSec = 600_000
        s.power = PowerSample(source: .battery, watts: 7.8, isCharging: false)
        s.networkDownBitsPerSec = 312_000_000
        s.networkUpBitsPerSec = 24_000_000
        s.ping = pingTargets(primaryMs: 14, primaryLoss: 0)
        s.levels = [.ping: .ok, .cpu: .ok, .memory: .ok, .disk: .ok, .power: .ok, .thermal: .ok]
        s.history = [
            SeriesKey.ping(1): wave(30, base: 14, amplitude: 3),
            SeriesKey.cpu: wave(30, base: 0.18, amplitude: 0.08, seed: 3),
            SeriesKey.memory: wave(30, base: 0.66, amplitude: 0.01, seed: 1),
            SeriesKey.power: wave(30, base: 7.8, amplitude: 2, seed: 5),
            SeriesKey.diskRead: wave(30, base: 2_000_000, amplitude: 1_500_000, seed: 2),
            SeriesKey.netDown: wave(30, base: 200e6, amplitude: 120e6, seed: 4),
            SeriesKey.netUp: wave(30, base: 20e6, amplitude: 10e6, seed: 7),
        ]
        return s
    }

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
        s.history[SeriesKey.ping(1)] = pingHistory
        s.history[SeriesKey.cpu] = wave(30, base: 0.85, amplitude: 0.08, seed: 3)
        return s
    }

    private static func pingTargets(primaryMs: Float, primaryLoss: Float) -> [PingTargetState] {
        let samples: [Float] = [3.1, primaryMs, 21, 34, 142]
        return PingTarget.defaults.enumerated().map { index, target in
            var values = wave(10, base: samples[index], amplitude: samples[index] * 0.08, seed: Float(index))
            values[9] = samples[index]
            if index == 1 && primaryLoss > 0 { values[3] = PingStats.lost }
            return PingTargetState(
                index: index, target: target, stats: PingStats.compute(values),
                isPrimary: index == PingTarget.defaultPrimaryIndex)
        }
    }
}
