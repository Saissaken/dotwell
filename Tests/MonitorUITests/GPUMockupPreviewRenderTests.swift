import AppKit
import MonitorCore
import SwiftUI
import XCTest

@testable import MonitorUI

/// Design mockup for a GPU card (not for merge). Renders the proposed card next to the real CPU card,
/// with sample data, so the proposal can be judged on real controls.
@MainActor
final class GPUMockupPreviewRenderTests: XCTestCase {
    func testRenderGPUMockups() throws {
        guard let dir = ProcessInfo.processInfo.environment["PREVIEW_DIR"] else {
            throw XCTSkip("Set PREVIEW_DIR to render previews")
        }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let content = VStack(alignment: .leading, spacing: PopoverLayout.spacing) {
                GroupLabel("Light use")
                row(cpu: 0.21, cpuApp: ("Safari", "8%"), gpu: 0.12, gpuCaption: "40 cores · 41 °C · 0.9 W",
                    gpuApp: ("Safari", "6%"), gpuBase: 0.12, seed: 2)
                GroupLabel("Playing a game")
                row(cpu: 0.34, cpuApp: ("Chess", "31%"), gpu: 0.94, gpuCaption: "40 cores · 68 °C · 14.2 W",
                    gpuApp: ("Chess", "87%"), gpuBase: 0.9, seed: 5)
            }
            .padding(PopoverLayout.padding)
            .frame(width: PopoverLayout.width)
            try render(content, appearance: appearance)
                .write(to: url.appendingPathComponent("mockup-gpu-card-\(mode).png"))
        }
    }

    private func row(
        cpu: Float, cpuApp: (String, String), gpu: Float, gpuCaption: String, gpuApp: (String, String),
        gpuBase: Float, seed: Float
    ) -> some View {
        HStack(alignment: .top, spacing: PopoverLayout.spacing) {
            MetricModule(
                symbol: "cpu", title: "CPU", level: .ok, reading: Format.percent(cpu),
                caption: "14 cores · 47 °C", topApp: topApp(cpuApp),
                values: SampleData.wave(30, base: cpu, amplitude: 0.06, seed: seed), maxValue: 1)
            MetricModule(
                symbol: "cube", title: "GPU", level: .ok, reading: Format.percent(gpu),
                caption: gpuCaption, topApp: topApp(gpuApp),
                values: SampleData.wave(30, base: gpuBase, amplitude: 0.07, seed: seed + 1), maxValue: 1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func topApp(_ app: (String, String)) -> TopAppRow {
        let path = app.0 == "Safari" ? "/Applications/Safari.app" : "/System/Applications/\(app.0).app"
        let usage = ProcessUsage(
            id: path, name: app.0, path: path, cpu: 0, memoryBytes: 0, diskBytesPerSec: 0, watts: 0)
        return TopAppRow(app: usage, value: app.1, icon: NSWorkspace.shared.icon(forFile: path))
    }

    private func render(_ content: some View, appearance: NSAppearance.Name) throws -> Data {
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
        guard let png = rep.representation(using: .png, properties: [:]) else { throw XCTSkip("No PNG") }
        return png
    }
}
