import Foundation
import MonitorCore
import SwiftUI  // MutableCollection.move(fromOffsets:toOffset:)

/// How network throughput is shown.
public enum NetworkUnit: String, CaseIterable, Codable, Sendable {
    /// Mbps, like internet plans and speed tests.
    case bits
    /// MB/s, like download progress in Finder and browsers.
    case bytes
}

/// One card of the popover as the person arranged it.
public struct WidgetSetting: Codable, Equatable, Identifiable, Sendable {
    public var module: Module
    public var isVisible: Bool
    /// Show the app using the most of this resource. Only some modules have one.
    public var showsTopApp: Bool

    public var id: Module { module }

    public init(module: Module, isVisible: Bool = true, showsTopApp: Bool = true) {
        self.module = module
        self.isVisible = isVisible
        self.showsTopApp = showsTopApp
    }

    public static let defaults: [WidgetSetting] = Module.allCases.map { WidgetSetting(module: $0) }

    /// Keeps the saved order and choices, drops unknown modules and appends new ones at the end.
    static func merged(_ saved: [WidgetSetting]) -> [WidgetSetting] {
        var seen = Set<Module>()
        var result = saved.filter { seen.insert($0.module).inserted }
        result += defaults.filter { !seen.contains($0.module) }
        return result
    }
}

/// Everything the person can change in Settings, saved in `UserDefaults` and applied right away.
///
/// The sampler only sees `configuration`, so `onConfigurationChange` fires just for the settings
/// that affect sampling; display-only settings (order, units) reach the popover through `@Published`.
@MainActor
public final class AppSettings: ObservableObject {
    @Published public var interval: SamplingInterval {
        didSet { store(interval.rawValue, .interval) }
    }
    @Published public var networkUnit: NetworkUnit {
        didSet { store(networkUnit.rawValue, .networkUnit) }
    }
    /// Show the local and public IP addresses in the Network card. Off also skips the public address lookup.
    @Published public var showsIPAddresses: Bool {
        didSet { store(showsIPAddresses, .showsIPAddresses) }
    }
    @Published public var widgets: [WidgetSetting] {
        didSet { storeJSON(widgets, .widgets) }
    }
    /// The host that stands for "the internet".
    @Published public var internetHost: InternetHost {
        didSet { store(internetHost.rawValue, .internetHost) }
    }
    /// The two cloud regions to compare with; nil turns a slot off.
    @Published public var regions: [CloudRegion?] {
        didSet { storeJSON(regions.map { $0.map(SavedRegion.init) }, .regions) }
    }
    /// The row that drives the status light.
    @Published public var primarySlot: PingSlot {
        didSet { store(primarySlot.rawValue, .primarySlot) }
    }
    @Published public var thresholds: Thresholds {
        didSet { storeJSON(thresholds, .thresholds) }
    }
    /// Metrics allowed to turn the status light yellow or red.
    @Published public var alerts: Set<MetricKind> {
        didSet { store(alerts.map(\.rawValue).sorted(), .alerts) }
    }

    /// Called after any change that the sampler needs to know about.
    public var onConfigurationChange: ((SamplerConfiguration) -> Void)?

    private let defaults: UserDefaults?
    private var lastConfiguration: SamplerConfiguration?

    private enum Key: String {
        case interval = "samplingInterval"
        case networkUnit
        case showsIPAddresses
        case widgets
        case internetHost
        case regions = "pingRegions"
        case primarySlot = "primaryPingSlot"
        case thresholds
        case alerts
    }

    /// Pass nil to keep everything in memory (tests, previews).
    public init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        func load<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
            guard let data = defaults?.data(forKey: key.rawValue) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        let savedInterval = defaults?.object(forKey: Key.interval.rawValue) as? Int
        interval = savedInterval.flatMap(SamplingInterval.init) ?? .oneSecond
        networkUnit = defaults?.string(forKey: Key.networkUnit.rawValue).flatMap(NetworkUnit.init) ?? .bits
        showsIPAddresses = defaults?.object(forKey: Key.showsIPAddresses.rawValue) as? Bool ?? true
        widgets = WidgetSetting.merged(load([WidgetSetting].self, .widgets) ?? [])
        internetHost = defaults?.string(forKey: Key.internetHost.rawValue).flatMap(InternetHost.init) ?? .cloudflare
        if let saved = load([SavedRegion?].self, .regions), saved.count == PingSlot.regionCount {
            regions = saved.map { $0.flatMap { CloudRegion.find($0.provider, $0.code) } }
        } else {
            regions = [CloudRegion.defaultFirst, CloudRegion.defaultSecond]
        }
        primarySlot = defaults?.string(forKey: Key.primarySlot.rawValue).flatMap(PingSlot.init) ?? .internet
        thresholds = load(Thresholds.self, .thresholds) ?? Thresholds()
        if let saved = defaults?.stringArray(forKey: Key.alerts.rawValue) {
            alerts = Set(saved.compactMap(MetricKind.init))
        } else {
            alerts = MetricKind.alertable
        }
        lastConfiguration = configuration
    }

    // MARK: - Derived

    public var configuration: SamplerConfiguration {
        SamplerConfiguration(
            interval: interval,
            targets: pingSlots.map(\.target),
            primaryIndex: pingSlots.firstIndex { $0.slot == effectivePrimarySlot } ?? 0,
            thresholds: thresholds,
            alerts: alerts,
            pingEnabled: isVisible(.ping) || alerts.contains(.ping),
            sampleTopApps: widgets.contains { $0.isVisible && $0.showsTopApp && $0.module.hasTopApp })
    }

    /// Whether the popover needs the IP addresses at all.
    public var wantsIPAddresses: Bool { showsIPAddresses && isVisible(.network) }

    public func isVisible(_ module: Module) -> Bool {
        widgets.first { $0.module == module }?.isVisible ?? true
    }

    public func showsTopApp(_ module: Module) -> Bool {
        module.hasTopApp && (widgets.first { $0.module == module }?.showsTopApp ?? true)
    }

    // MARK: - Ping targets

    /// The rows of the ping card, in order: router, ISP, internet, then the regions that are on.
    public var pingSlots: [(slot: PingSlot, target: PingTarget)] {
        var slots: [(slot: PingSlot, target: PingTarget)] = [
            (.router, .router), (.isp, .isp), (.internet, internetHost.target),
        ]
        for (index, region) in regions.enumerated() {
            if let region, let slot = PingSlot.region(index) { slots.append((slot: slot, target: region.target)) }
        }
        return slots
    }

    /// `primarySlot`, or the internet host when it points at a region that is off.
    public var effectivePrimarySlot: PingSlot {
        pingSlots.contains { $0.slot == primarySlot } ? primarySlot : .internet
    }

    public func setRegion(_ region: CloudRegion?, at index: Int) {
        guard regions.indices.contains(index) else { return }
        regions[index] = region
    }

    public func moveWidgets(from source: IndexSet, to destination: Int) {
        widgets.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Restore

    public func restoreDefaultTargets() {
        internetHost = .cloudflare
        regions = [CloudRegion.defaultFirst, CloudRegion.defaultSecond]
        primarySlot = .internet
    }

    public func restoreDefaultAlerts() {
        thresholds = Thresholds()
        alerts = MetricKind.alertable
    }

    public func restoreDefaultWidgets() {
        widgets = WidgetSetting.defaults
    }

    // MARK: - Storage

    private func store(_ value: Any, _ key: Key) {
        defaults?.set(value, forKey: key.rawValue)
        configurationMayHaveChanged()
    }

    private func storeJSON<T: Encodable>(_ value: T, _ key: Key) {
        if let data = try? JSONEncoder().encode(value) { defaults?.set(data, forKey: key.rawValue) }
        configurationMayHaveChanged()
    }

    private func configurationMayHaveChanged() {
        let configuration = self.configuration
        guard configuration != lastConfiguration else { return }
        lastConfiguration = configuration
        onConfigurationChange?(configuration)
    }
}

/// A row of the ping card.
public enum PingSlot: String, CaseIterable, Codable, Sendable {
    case router, isp, internet, region1, region2

    static let regionCount = 2

    static func region(_ index: Int) -> PingSlot? {
        switch index {
        case 0: return .region1
        case 1: return .region2
        default: return nil
        }
    }
}

/// A region as saved: provider and code only, so a later version can fix an endpoint.
private struct SavedRegion: Codable {
    var provider: CloudProvider
    var code: String

    init(_ region: CloudRegion) {
        provider = region.provider
        code = region.code
    }
}

extension Module {
    /// Modules that can show the app using the most of their resource.
    public var hasTopApp: Bool {
        switch self {
        case .cpu, .memory, .disk, .power: return true
        case .ping, .network, .thermal: return false
        }
    }

    public var title: String {
        switch self {
        case .ping: return "Ping"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .power: return "Power"
        case .disk: return "Disk"
        case .network: return "Network"
        case .thermal: return "Thermal"
        }
    }

    public var symbol: String {
        switch self {
        case .ping: return "network"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .power: return "battery.75percent"
        case .disk: return "internaldrive"
        case .network: return "arrow.up.arrow.down"
        case .thermal: return "thermometer.medium"
        }
    }
}
