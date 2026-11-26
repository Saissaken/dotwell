import AppKit
import MonitorCore
import MonitorUI
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
    private let settings: AppSettings
    private let updater: Updater
    private let openSettings: () -> Void
    private var model: PopoverModel?
    /// Lives as long as the app so the public address stays cached between openings.
    private let addressMonitor = NetworkAddressMonitor()

    init(sampler: Sampler, settings: AppSettings, updater: Updater, openSettings: @escaping () -> Void) {
        self.sampler = sampler
        self.settings = settings
        self.updater = updater
        self.openSettings = openSettings
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        guard let button = statusItem.button else { return }
        let glyph = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Dotwell")
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
            let model = PopoverModel(snapshot: sampler.latest())
            model.openSettings = { [weak self] in
                self?.popover.performClose(nil)
                self?.openSettings()
            }
            model.quit = { NSApplication.shared.terminate(nil) }
            if updater.isAvailable {
                model.checkForUpdates = { [weak self] in self?.updater.checkForUpdates(nil) }
            }
            model.onRangeChange = { [weak self] range in self?.sampler.setDetailed(true, range: range) }
            self.model = model
            sampler.setDetailed(true, range: model.range)
            if settings.wantsIPAddresses {
                addressMonitor.onChange = { [weak model] in model?.addresses = $0 }
                addressMonitor.start()
                model.addresses = addressMonitor.addresses
            }
            popover.contentViewController = NSHostingController(rootView: PopoverView(model: model, settings: settings))
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Builds the menu on demand and releases it once it closes.
    private func showMenu(from button: NSStatusBarButton) {
        if popover.isShown { popover.performClose(button) }
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        if updater.isAvailable {
            let check = NSMenuItem(
                title: "Check for Updates…", action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "")
            check.target = updater
            menu.addItem(check)
        }
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Dotwell", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))
        statusItem.menu = menu
        button.performClick(nil)  // shows the menu and returns once it closes
        statusItem.menu = nil  // left clicks go back to the popover
    }

    @objc private func showSettings(_ sender: Any?) {
        openSettings()
    }

    func popoverDidClose(_ notification: Notification) {
        sampler.setDetailed(false, range: .seconds30)
        addressMonitor.stop()
        addressMonitor.onChange = nil
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
