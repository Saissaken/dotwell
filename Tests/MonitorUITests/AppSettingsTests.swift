import MonitorCore
import XCTest

@testable import MonitorUI

@MainActor
final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "com.saissaken.Dotwell.tests.settings"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaultsMatchTheBuiltInConfiguration() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.configuration, SamplerConfiguration())
        XCTAssertEqual(settings.widgets.map(\.module), Module.allCases)
        XCTAssertEqual(settings.networkUnit, .bits)
    }

    func testChangesPersistAcrossLaunches() {
        let settings = AppSettings(defaults: defaults)
        settings.interval = .fiveSeconds
        settings.networkUnit = .bytes
        settings.thresholds.pingWarningMs = 50
        settings.alerts.remove(.cpu)
        settings.internetHost = .quad9
        settings.setRegion(CloudRegion.find(.azure, "brazilsouth"), at: 1)
        settings.primarySlot = .region2
        settings.moveWidgets(from: [6], to: 0)
        settings.widgets[1].showsTopApp = false

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.interval, .fiveSeconds)
        XCTAssertEqual(reloaded.networkUnit, .bytes)
        XCTAssertEqual(reloaded.thresholds.pingWarningMs, 50)
        XCTAssertFalse(reloaded.alerts.contains(.cpu))
        XCTAssertEqual(reloaded.internetHost, .quad9)
        XCTAssertEqual(reloaded.regions, [CloudRegion.defaultFirst, CloudRegion.find(.azure, "brazilsouth")])
        XCTAssertEqual(reloaded.configuration.primaryIndex, 5)
        XCTAssertEqual(reloaded.widgets, settings.widgets)
        XCTAssertEqual(reloaded.configuration, settings.configuration)
    }

    func testConfigurationChangesAreReported() {
        let settings = AppSettings(defaults: nil)
        var received: [SamplerConfiguration] = []
        settings.onConfigurationChange = { received.append($0) }
        settings.networkUnit = .bytes  // display only
        settings.interval = .twoSeconds
        settings.interval = .twoSeconds  // unchanged
        XCTAssertEqual(received.map(\.interval), [.twoSeconds])
    }

    func testPingRows() {
        let settings = AppSettings(defaults: nil)
        XCTAssertEqual(settings.configuration.targets, PingTarget.defaults)
        XCTAssertEqual(settings.configuration.primaryIndex, PingTarget.defaultPrimaryIndex)

        settings.primarySlot = .region2
        XCTAssertEqual(settings.configuration.primaryIndex, 5)
        settings.setRegion(nil, at: 0)
        XCTAssertEqual(
            settings.configuration.targets.map(\.name), ["Router", "ISP", "DNS", "Cloudflare", "AWS Virginia"])
        XCTAssertEqual(settings.configuration.primaryIndex, 4, "the primary follows its row")
        settings.setRegion(nil, at: 1)
        XCTAssertEqual(settings.effectivePrimarySlot, .internet, "a region that is off falls back to the internet")
        XCTAssertEqual(settings.configuration.primaryIndex, 3)

        settings.restoreDefaultTargets()
        XCTAssertEqual(settings.configuration.targets, PingTarget.defaults)
    }

    func testHidingCardsStopsTheWorkBehindThem() {
        let settings = AppSettings(defaults: nil)
        func setVisible(_ module: Module, _ visible: Bool) {
            settings.widgets[settings.widgets.firstIndex { $0.module == module }!].isVisible = visible
        }
        setVisible(.ping, false)
        XCTAssertTrue(settings.configuration.pingEnabled, "the ping alert still needs pings")
        settings.alerts.remove(.ping)
        XCTAssertFalse(settings.configuration.pingEnabled)

        for index in settings.widgets.indices { settings.widgets[index].showsTopApp = false }
        XCTAssertFalse(settings.configuration.sampleTopApps)
        settings.widgets[settings.widgets.firstIndex { $0.module == .disk }!].showsTopApp = true
        XCTAssertTrue(settings.configuration.sampleTopApps)
        setVisible(.disk, false)
        XCTAssertFalse(settings.configuration.sampleTopApps)
    }

    func testSavedWidgetsGainNewModules() {
        let saved = [WidgetSetting(module: .network, isVisible: false), WidgetSetting(module: .network)]
        let merged = WidgetSetting.merged(saved)
        XCTAssertEqual(merged.first, WidgetSetting(module: .network, isVisible: false))
        XCTAssertEqual(merged.count, Module.allCases.count)
    }

    func testVisibleModulesFollowTheSettings() {
        var snap = Snapshot()
        var widgets = WidgetSetting.defaults
        XCTAssertEqual(Module.visible(in: snap, widgets: widgets), [.ping, .cpu, .memory, .disk, .network])
        snap.power = PowerSample(source: .battery, watts: 5, isCharging: false)
        snap.thermal = .serious
        widgets.move(fromOffsets: [6], toOffset: 0)
        widgets[2].isVisible = false  // CPU
        XCTAssertEqual(
            Module.visible(in: snap, widgets: widgets), [.network, .ping, .memory, .power, .disk, .thermal])
    }
}
