import MonitorCore
import SwiftUI

/// A page of the Settings window, listed in its sidebar like System Settings.
public enum SettingsPage: Hashable, Sendable {
    case general
    /// Everything about one card of the popover: whether it shows, its options and its alert.
    case widget(Module)
    case updates
    case about

    /// Saved to reopen the window where the person left it.
    public var id: String {
        switch self {
        case .general: return "general"
        case .widget(let module): return "widget.\(module.rawValue)"
        case .updates: return "updates"
        case .about: return "about"
        }
    }

    public init?(id: String) {
        switch id {
        case "general": self = .general
        case "updates": self = .updates
        case "about": self = .about
        default:
            guard id.hasPrefix("widget."), let module = Module(rawValue: String(id.dropFirst(7))) else { return nil }
            self = .widget(module)
        }
    }

    public var title: String {
        switch self {
        case .general: return "General"
        case .widget(let module): return module.settingsTitle
        case .updates: return "Updates"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .widget(let module): return module.settingsSymbol
        case .updates: return "arrow.triangle.2.circlepath"
        case .about: return "info.circle.fill"
        }
    }

    /// The tile color behind the icon, as in System Settings.
    var tint: Color {
        switch self {
        case .general: return .gray
        case .widget(let module):
            switch module {
            case .ping: return .blue
            case .cpu: return .orange
            case .gpu: return .pink
            case .memory: return .purple
            case .power: return .green
            case .disk: return .indigo
            case .network: return .teal
            }
        case .updates: return .blue
        case .about: return .gray
        }
    }

    /// Extra words the sidebar search matches, so "IP" finds Network and "heat" finds CPU.
    var keywords: [String] {
        switch self {
        case .general: return ["login", "startup", "interval", "readings", "energy", "battery life", "website"]
        case .widget(let module):
            switch module {
            case .ping: return ["latency", "router", "isp", "dns", "cloudflare", "aws", "gcp", "azure", "region"]
            case .cpu:
                return [
                    "processor", "temperature", "heat", "thermal", "slow", "throttle", "busiest app", "fan", "core",
                    "activity monitor",
                ]
            case .gpu: return ["graphics", "apple silicon", "watts", "temperature", "windowserver", "busiest app"]
            case .memory: return ["ram", "pressure", "swap", "busiest app"]
            case .power: return ["battery", "watts", "energy", "adapter", "charging", "busiest app"]
            case .disk: return ["storage", "free space", "ssd", "read", "write", "busiest app"]
            case .network: return ["speed", "mbps", "bandwidth", "ip address", "public", "local", "units"]
            }
        case .updates: return ["version", "sparkle", "automatic", "download", "nightly", "beta", "channel"]
        case .about: return ["version", "website", "license", "github", "source"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([title] + keywords).contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

extension Module {
    /// The name in Settings. "Battery" for the power card, which only exists on Macs with one.
    var settingsTitle: String { self == .power ? "Battery" : title }

    var settingsSymbol: String {
        switch self {
        case .ping: return "network"
        case .cpu: return "cpu"
        case .gpu: return "cube"
        case .memory: return "memorychip"
        case .power: return "battery.75percent"
        case .disk: return "internaldrive"
        case .network: return "arrow.up.arrow.down"
        }
    }

    /// One line under the page title.
    var settingsSummary: String {
        switch self {
        case .ping: return "How long your router, your provider and the internet take to answer."
        case .cpu: return "How busy the processor is, how hot it runs, and whether macOS is slowing it down."
        case .gpu: return "How busy the graphics processor is, and the power it draws. Only on Apple silicon."
        case .memory: return "How much memory apps use, and whether macOS is running short."
        case .power: return "How much power the Mac draws. Only shown on Macs with a battery."
        case .disk: return "Free space on the startup disk, and how fast it's being read and written."
        case .network: return "How fast this Mac is downloading and uploading, and its IP addresses."
        }
    }
}

/// Which page is showing, with Back and Forward history like System Settings.
@MainActor
public final class SettingsNavigation: ObservableObject {
    @Published public private(set) var page: SettingsPage
    @Published public var query = ""
    @Published public private(set) var canGoBack = false
    @Published public private(set) var canGoForward = false
    /// A region slot whose chooser should open on the Ping page, as asked from a ping row's menu.
    @Published public var choosingRegion: Int?

    private var back: [SettingsPage] = []
    private var forward: [SettingsPage] = []

    public init(page: SettingsPage = .general) {
        self.page = page
    }

    /// Opens a page, as clicking it in the sidebar does.
    public func show(_ newPage: SettingsPage) {
        guard newPage != page else { return }
        back.append(page)
        forward.removeAll()
        page = newPage
        update()
    }

    public func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(page)
        page = previous
        update()
    }

    public func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(page)
        page = next
        update()
    }

    private func update() {
        canGoBack = !back.isEmpty
        canGoForward = !forward.isEmpty
    }
}
