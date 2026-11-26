import AppKit
import Sparkle

/// Wraps Sparkle's standard updater so the rest of the app does not depend on it.
///
/// Sparkle checks the appcast once a day, downloads updates in the background and installs them
/// when the app quits. The feed URL and EdDSA public key come from `Info.plist`.
@MainActor
final class Updater: NSObject, NSMenuItemValidation {
    private let controller: SPUStandardUpdaterController?

    override init() {
        // `swift run` builds have no bundle Info.plist, hence no feed: updates are disabled there.
        let info = Bundle.main.infoDictionary ?? [:]
        if info["SUFeedURL"] != nil, info["SUPublicEDKey"] != nil {
            controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            controller = nil
        }
        super.init()
    }

    /// Whether this build can update itself at all.
    var isAvailable: Bool { controller != nil }

    @objc func checkForUpdates(_ sender: Any?) {
        // The app has no Dock icon, so bring it forward or Sparkle's window opens behind others.
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(checkForUpdates(_:)) else { return true }
        return controller?.updater.canCheckForUpdates ?? false
    }
}
