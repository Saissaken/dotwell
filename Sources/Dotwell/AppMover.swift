import AppKit

/// Offers, on launch, to move the app into the Applications folder when it runs from somewhere else
/// (Downloads, the disk image). Updates and launch at login are only reliable from a stable location.
/// Once installed, it also offers to eject the installer disk image and move it to the Trash.
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

    /// When the installer disk image is still mounted, offers to eject it and trash the downloaded `.dmg`.
    /// Cheap when there is nothing to do: it only looks at the mounted volumes' top level.
    static func offerInstallerCleanup() {
        guard isInApplicationsFolder(Bundle.main.bundleURL.resolvingSymlinksInPath()),
            let volume = installerVolume()
        else { return }
        let image = diskImagePath(mountedAt: volume)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Eject the Dotwell installer?"
        alert.informativeText =
            "Dotwell is installed in the Applications folder, so the disk image is no longer needed."
        if let image {
            alert.addButton(withTitle: "Eject and Move to Trash")
            alert.addButton(withTitle: "Eject")
            alert.informativeText += " \"\(image.lastPathComponent)\" can go to the Trash."
        } else {
            alert.addButton(withTitle: "Eject")
        }
        alert.addButton(withTitle: "Keep").keyEquivalent = "\u{1b}"
        let response = alert.runModal()
        let trash = image != nil && response == .alertFirstButtonReturn
        let eject = trash || response == (image != nil ? .alertSecondButtonReturn : .alertFirstButtonReturn)
        guard eject else { return }
        ejectWhenFree(volume, thenTrash: trash ? image : nil, attemptsLeft: 10)
    }

    /// A mounted volume, other than the one we run from, whose top level holds this same app.
    private static func installerVolume() -> URL? {
        let running = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let volumes =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [], options: [.skipHiddenVolumes]) ?? []
        return volumes.first { volume in
            guard volume.path.hasPrefix("/Volumes/"), !running.path.hasPrefix(volume.path + "/") else { return false }
            let candidate = volume.appendingPathComponent(running.lastPathComponent)
            return Bundle(url: candidate)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
    }

    /// The `.dmg` file backing a mount point, from `hdiutil info`. Only runs when an installer is mounted.
    private static func diskImagePath(mountedAt volume: URL) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let images = info["images"] as? [[String: Any]]
        else { return nil }
        for image in images {
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            let mountPoints = entities.compactMap { $0["mount-point"] as? String }
            if mountPoints.contains(volume.path), let path = image["image-path"] as? String,
                FileManager.default.fileExists(atPath: path)
            {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Ejects the volume, retrying while the copy we just moved away from is still quitting.
    private static func ejectWhenFree(_ volume: URL, thenTrash image: URL?, attemptsLeft: Int) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            if let image { try? FileManager.default.trashItem(at: image, resultingItemURL: nil) }
        } catch {
            guard attemptsLeft > 1 else {
                NSLog("AppMover: could not eject \(volume.path): \(error)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                ejectWhenFree(volume, thenTrash: image, attemptsLeft: attemptsLeft - 1)
            }
        }
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
