import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+). Enabled by default on first launch.
enum LoginItem {
    private static let didRegisterKey = "didRegisterLoginItem"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func registerOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: didRegisterKey) else { return }
        if setEnabled(true) {
            UserDefaults.standard.set(true, forKey: didRegisterKey)
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            NSLog("LoginItem: \(enabled ? "register" : "unregister") failed: \(error)")
            return false
        }
    }
}
