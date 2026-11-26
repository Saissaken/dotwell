import AppKit
import SwiftUI
import MonitorCore

/// Owns the menu bar item and the popover. The popover's SwiftUI tree is created
/// on open and released on close, so nothing is retained while it is hidden.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let dot = StatusDotView(frame: .zero)
    private var level: HealthLevel = .ok

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        guard let button = statusItem.button else { return }
        let glyph = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Monitor de recursos")
        glyph?.isTemplate = true // follows light/dark menu bar automatically
        button.image = glyph
        button.target = self
        button.action = #selector(togglePopover(_:))

        dot.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(dot)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            dot.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -3),
        ])
        apply(level: .ok)
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
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.contentViewController = NSHostingController(rootView: PopoverView())
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
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
