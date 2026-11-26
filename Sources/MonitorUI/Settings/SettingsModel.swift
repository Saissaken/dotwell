import Foundation
import MonitorCore

/// Settings that live outside `AppSettings` because the system owns them: the login item and
/// Sparkle's update preferences. The app target fills in the closures.
@MainActor
public final class SettingsModel: ObservableObject {
    public let settings: AppSettings
    @Published public var launchAtLogin: Bool
    /// Nil when this build can't update itself (e.g. `swift run`).
    public let updates: UpdateSettings?
    /// Applies the launch-at-login setting and returns the resulting state.
    public var setLaunchAtLogin: ((Bool) -> Bool)?
    /// Shown on the Updates and About pages, e.g. "0.4.0 (14)".
    public var version = SettingsModel.bundleVersion

    static var bundleVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "development"
        guard let build = info["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }

    public init(settings: AppSettings, launchAtLogin: Bool, updates: UpdateSettings?) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.updates = updates
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = setLaunchAtLogin?(enabled) ?? enabled
    }
}

/// A view of the updater's preferences, so the UI doesn't depend on Sparkle.
@MainActor
public final class UpdateSettings: ObservableObject {
    public struct Backend {
        public var automaticallyChecks: () -> Bool
        public var setAutomaticallyChecks: (Bool) -> Void
        public var automaticallyDownloads: () -> Bool
        public var setAutomaticallyDownloads: (Bool) -> Void
        public var lastCheck: () -> Date?
        public var checkNow: () -> Void

        public init(
            automaticallyChecks: @escaping () -> Bool, setAutomaticallyChecks: @escaping (Bool) -> Void,
            automaticallyDownloads: @escaping () -> Bool, setAutomaticallyDownloads: @escaping (Bool) -> Void,
            lastCheck: @escaping () -> Date?, checkNow: @escaping () -> Void
        ) {
            self.automaticallyChecks = automaticallyChecks
            self.setAutomaticallyChecks = setAutomaticallyChecks
            self.automaticallyDownloads = automaticallyDownloads
            self.setAutomaticallyDownloads = setAutomaticallyDownloads
            self.lastCheck = lastCheck
            self.checkNow = checkNow
        }
    }

    private let backend: Backend
    @Published public var automaticallyChecks: Bool {
        didSet { backend.setAutomaticallyChecks(automaticallyChecks) }
    }
    @Published public var automaticallyDownloads: Bool {
        didSet { backend.setAutomaticallyDownloads(automaticallyDownloads) }
    }
    @Published public private(set) var lastCheck: Date?

    public init(_ backend: Backend) {
        self.backend = backend
        automaticallyChecks = backend.automaticallyChecks()
        automaticallyDownloads = backend.automaticallyDownloads()
        lastCheck = backend.lastCheck()
    }

    func checkNow() {
        backend.checkNow()
    }

    func refresh() {
        lastCheck = backend.lastCheck()
    }
}
