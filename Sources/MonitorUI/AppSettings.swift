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
    @Published public var widgets: [WidgetSetting] {
        didSet { storeJSON(widgets, .widgets) }
    }
    @Published public private(set) var pingTargets: [PingTarget] {
        didSet { storeJSON(pingTargets, .pingTargets) }
    }
    /// Index into `pingTargets` of the host that drives the status light.
    @Published public var primaryTargetIndex: Int {
        didSet { store(primaryTargetIndex, .primaryTarget) }
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
        case widgets
        case pingTargets
        case primaryTarget = "primaryPingTarget"
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
        widgets = WidgetSetting.merged(load([WidgetSetting].self, .widgets) ?? [])
        let targets = load([PingTarget].self, .pingTargets) ?? PingTarget.defaults
        pingTargets = targets
        let primary = defaults?.object(forKey: Key.primaryTarget.rawValue) as? Int ?? PingTarget.defaultPrimaryIndex
        primaryTargetIndex = min(max(0, primary), max(0, targets.count - 1))
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
            targets: pingTargets,
            primaryIndex: primaryTargetIndex,
            thresholds: thresholds,
            alerts: alerts,
            pingEnabled: isVisible(.ping) || alerts.contains(.ping),
            sampleTopApps: widgets.contains { $0.isVisible && $0.showsTopApp && $0.module.hasTopApp })
    }

    public func isVisible(_ module: Module) -> Bool {
        widgets.first { $0.module == module }?.isVisible ?? true
    }

    public func showsTopApp(_ module: Module) -> Bool {
        module.hasTopApp && (widgets.first { $0.module == module }?.showsTopApp ?? true)
    }

    // MARK: - Ping targets

    public var canAddTarget: Bool { pingTargets.count < PingTarget.maximumCount }

    public func addTarget(_ target: PingTarget) {
        guard canAddTarget else { return }
        pingTargets.append(target)
    }

    public func replaceTarget(at index: Int, with target: PingTarget) {
        guard pingTargets.indices.contains(index) else { return }
        pingTargets[index] = target
    }

    /// Removes targets, keeping the same primary when it survives (or the first one otherwise).
    public func removeTargets(at offsets: IndexSet) {
        guard pingTargets.count - offsets.count >= 1 else { return }  // keep at least one
        let primary = pingTargets.indices.contains(primaryTargetIndex) ? primaryTargetIndex : 0
        let primaryRemoved = offsets.contains(primary)
        let shift = offsets.count(in: 0..<primary)
        var targets = pingTargets
        for index in offsets.sorted(by: >) where targets.indices.contains(index) { targets.remove(at: index) }
        pingTargets = targets
        primaryTargetIndex = primaryRemoved ? 0 : primary - shift
    }

    public func moveTargets(from source: IndexSet, to destination: Int) {
        var indices = Array(pingTargets.indices)
        indices.move(fromOffsets: source, toOffset: destination)
        let primary = primaryTargetIndex
        pingTargets = indices.map { pingTargets[$0] }
        primaryTargetIndex = indices.firstIndex(of: primary) ?? 0
    }

    public func moveWidgets(from source: IndexSet, to destination: Int) {
        widgets.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Restore

    public func restoreDefaultTargets() {
        pingTargets = PingTarget.defaults
        primaryTargetIndex = PingTarget.defaultPrimaryIndex
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
