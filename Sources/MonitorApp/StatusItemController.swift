import AppKit
import MonitorCore
import SwiftUI

/// Owns the menu bar item and the popover. The popover's SwiftUI tree is created
/// on open and released on close, so nothing is retained while it is hidden.
/// Right-click (or Control-click) opens a small menu with app commands instead.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let dot = StatusDotView(frame: .zero)
    private var level: HealthLevel = .ok
    private let sampler: Sampler
    private let updater: Updater
    private var latest = Snapshot()
    private var model: PopoverModel?

    init(sampler: Sampler, updater: Updater) {
        self.sampler = sampler
        self.updater = updater
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        guard let button = statusItem.button else { return }
        let glyph = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Resource monitor")
        glyph?.isTemplate = true  // follows light/dark menu bar automatically
        button.image = glyph
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        dot.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(dot)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            dot.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -3),
        ])
        apply(level: .ok)

        sampler.onSnapshot = { [weak self] snap in self?.receive(snap) }
    }

    private func receive(_ snap: Snapshot) {
        latest = snap
        update(level: snap.overall)
        model?.snapshot = snap
    }

    /// Redraws only when the level actually changes.
    func update(level newLevel: HealthLevel) {
        guard newLevel != level else { return }
        apply(level: newLevel)
    }

    private func apply(level newLevel: HealthLevel) {
        level = newLevel
        switch newLevel {
        case .ok: dot.color = .systemGreen
        case .warning: dot.color = .systemYellow
        case .critical: dot.color = .systemRed
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu(from: sender)
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            let model = PopoverModel(snapshot: latest)
            model.onRangeChange = { [weak self] range in self?.sampler.setDetailed(true, range: range) }
            self.model = model
            sampler.setDetailed(true, range: model.range)
            popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Builds the menu on demand and releases it once it closes.
    private func showMenu(from button: NSStatusBarButton) {
        if popover.isShown { popover.performClose(button) }
        let menu = NSMenu()
        if updater.isAvailable {
            let check = NSMenuItem(
                title: "Check for Updates…", action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "")
            check.target = updater
            menu.addItem(check)
            menu.addItem(.separator())
        }
        menu.addItem(
            NSMenuItem(
                title: "Quit Mac Resource Monitor", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))
        statusItem.menu = menu
        button.performClick(nil)  // shows the menu and returns once it closes
        statusItem.menu = nil  // left clicks go back to the popover
    }

    func popoverDidClose(_ notification: Notification) {
        sampler.setDetailed(false, range: .seconds30)
        model = nil
        popover.contentViewController = nil
    }
}

/// Small colored status dot drawn over the template glyph.
final class StatusDotView: NSView {
    var color: NSColor = .systemGreen {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    // Clicks go through to the status bar button.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
