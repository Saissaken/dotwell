import AppKit

/// Offers, on launch, to move the app into the Applications folder when it runs from somewhere else
/// (Downloads, the disk image). Updates and launch at login are only reliable from a stable location.
@MainActor
enum AppMover {
    private static let suppressKey = "suppressMoveToApplications"

    /// Returns `true` when the app moved itself and is relaunching; the caller should stop launching.
    static func moveIfNeeded() -> Bool {
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard bundle.pathExtension == "app",  // `swift run` builds are not bundles
            !isInApplicationsFolder(bundle),
            !UserDefaults.standard.bool(forKey: suppressKey)
        else { return false }

        let folder = applicationsFolder()
        let destination = folder.appendingPathComponent(bundle.lastPathComponent)
        guard confirm() else { return false }

        do {
            try install(bundle, at: destination)
        } catch {
            NSLog("AppMover: could not move to \(folder.path): \(error)")
            let alert = NSAlert(error: error)
            alert.messageText = "Could not move Dotwell to the Applications folder."
            alert.runModal()
            return false
        }
        trashOriginal(bundle)
        relaunch(destination)
        return true
    }

    private static func isInApplicationsFolder(_ url: URL) -> Bool {
        let parents = FileManager.default.urls(for: .applicationDirectory, in: .allDomainsMask).map(\.path)
        return parents.contains { url.path.hasPrefix($0 + "/") }
    }

    /// `/Applications` when writable (admin users), otherwise `~/Applications`, which needs no password.
    private static func applicationsFolder() -> URL {
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if FileManager.default.isWritableFile(atPath: system.path) { return system }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    }

    private static func confirm() -> Bool {
        NSApp.activate(ignoringOtherApps: true)  // no Dock icon, so the alert would open behind other windows
        let alert = NSAlert()
        alert.messageText = "Move to Applications folder?"
        alert.informativeText =
            "Dotwell works best from the Applications folder, where it can update itself and open at login."
        alert.addButton(withTitle: "Move to Applications Folder")
        alert.addButton(withTitle: "Do Not Move").keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not ask again"
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: suppressKey)
        }
        return response == .alertFirstButtonReturn
    }

    private static func install(_ source: URL, at destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            // Quit an older copy that is still running from there before replacing it.
            let identifier = Bundle.main.bundleIdentifier ?? ""
            let target = destination.resolvingSymlinksInPath()
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            where app.bundleURL?.resolvingSymlinksInPath() == target {
                app.terminate()
            }
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: source, to: destination)
        // The person already allowed this copy to open; keep Gatekeeper from translocating it again.
        removeQuarantine(destination)
    }

    private static func removeQuarantine(_ root: URL) {
        let name = "com.apple.quarantine"
        removexattr(root.path, name, XATTR_NOFOLLOW)
        let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let item = items?.nextObject() as? URL {
            removexattr(item.path, name, XATTR_NOFOLLOW)
        }
    }

    /// Removes the copy we launched from, unless it lives on a read-only disk image. When Gatekeeper
    /// translocated the app, the bundle path is a temporary mount and the real copy is elsewhere.
    private static func trashOriginal(_ bundle: URL) {
        let original = translocationOriginal(of: bundle) ?? bundle
        guard !original.path.hasPrefix("/Volumes/") else { return }
        try? FileManager.default.trashItem(at: original, resultingItemURL: nil)
    }

    /// Resolves Gatekeeper's App Translocation through Security.framework's
    /// `SecTranslocateCreateOriginalPathForURL`, which has no public header.
    private static func translocationOriginal(of url: URL) -> URL? {
        typealias CreateOriginalPath =
            @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard url.path.contains("/AppTranslocation/"),
            let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
            let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL")
        else { return nil }
        let createOriginalPath = unsafeBitCast(symbol, to: CreateOriginalPath.self)
        return createOriginalPath(url as CFURL, nil)?.takeRetainedValue() as URL?
    }

    private static func relaunch(_ app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            if let error { NSLog("AppMover: relaunch failed: \(error)") }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
