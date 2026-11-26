import AppKit
import MonitorUI
import Sparkle

/// Wraps Sparkle's standard updater so the rest of the app does not depend on it.
///
/// Sparkle checks the appcast once a day, downloads updates in the background and installs them
/// when the app quits. The feed URL and EdDSA public key come from `Info.plist`.
///
/// People who opt into nightly builds read the nightly feed instead, which carries the newest build
/// of `main` on Sparkle's "nightly" channel plus the latest release. See docs/RELEASING.md.
@MainActor
final class Updater: NSObject, NSMenuItemValidation {
    private let channel: ChannelDelegate
    private let controller: SPUStandardUpdaterController?

    override init() {
        // `swift run` builds have no bundle Info.plist, hence no feed: updates are disabled there.
        let info = Bundle.main.infoDictionary ?? [:]
        let channel = ChannelDelegate()
        self.channel = channel
        if info["SUFeedURL"] != nil, info["SUPublicEDKey"] != nil {
            // Sparkle keeps a weak reference to its delegate; `channel` lives as long as we do.
            controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: channel, userDriverDelegate: nil)
        } else {
            controller = nil
        }
        super.init()
    }

    /// Switches between official releases and nightly builds. Turning nightlies on checks right
    /// away; turning them off keeps the installed build until a newer release comes out, since
    /// Sparkle never downgrades.
    private func setNightly(_ enabled: Bool) {
        guard channel.nightly != enabled, let updater = controller?.updater else { return }
        channel.nightly = enabled
        updater.resetUpdateCycle()
        if enabled, updater.canCheckForUpdates {
            updater.checkForUpdatesInBackground()
        }
    }

    /// Whether this build can update itself at all.
    var isAvailable: Bool { controller != nil }

    @objc func checkForUpdates(_ sender: Any?) {
        // The app has no Dock icon, so bring it forward or Sparkle's window opens behind others.
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(sender)
    }

    /// The updater's preferences for the Settings window; Sparkle saves them itself.
    func makeSettings() -> UpdateSettings? {
        guard let updater = controller?.updater else { return nil }
        return UpdateSettings(
            UpdateSettings.Backend(
                automaticallyChecks: { updater.automaticallyChecksForUpdates },
                setAutomaticallyChecks: { updater.automaticallyChecksForUpdates = $0 },
                automaticallyDownloads: { updater.automaticallyDownloadsUpdates },
                setAutomaticallyDownloads: { updater.automaticallyDownloadsUpdates = $0 },
                nightly: { [channel] in channel.nightly },
                setNightly: { [weak self] in self?.setNightly($0) },
                lastCheck: { updater.lastUpdateCheckDate },
                checkNow: { [weak self] in self?.checkForUpdates(nil) }))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(checkForUpdates(_:)) else { return true }
        return controller?.updater.canCheckForUpdates ?? false
    }
}

/// Points Sparkle at the nightly feed and channel while nightly builds are on.
final class ChannelDelegate: NSObject, SPUUpdaterDelegate {
    static let nightlyChannel = "nightly"
    static let nightlyFeedURL =
        "https://github.com/Saissaken/dotwell/releases/download/nightly/appcast.xml"
    private static let defaultsKey = "NightlyUpdates"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var nightly: Bool {
        get { defaults.bool(forKey: Self.defaultsKey) }
        set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }

    /// Nil keeps `SUFeedURL` from Info.plist (official releases only).
    func feedURLString(for updater: SPUUpdater) -> String? {
        nightly ? Self.nightlyFeedURL : nil
    }

    /// Items without a channel are always allowed, so releases in the nightly feed still apply.
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        nightly ? [Self.nightlyChannel] : []
    }
}
