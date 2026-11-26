import MonitorCore
import SwiftUI

/// The content of one Settings tab. The app hosts each tab in a toolbar-style tab view controller,
/// the same window style as Safari's or Xcode's settings.
public struct SettingsView: View {
    private let tab: SettingsTab
    @ObservedObject private var model: SettingsModel

    public init(tab: SettingsTab, model: SettingsModel) {
        self.tab = tab
        self.model = model
    }

    /// Every tab has the same width, so switching tabs only changes the window's height.
    static let width: CGFloat = 540

    public var body: some View {
        Group {
            switch tab {
            case .general: GeneralSettingsView(model: model, settings: model.settings)
            case .widgets: WidgetSettingsView(settings: model.settings)
            case .ping: PingSettingsView(settings: model.settings)
            case .alerts: AlertSettingsView(settings: model.settings)
            case .updates: UpdateSettingsView(updates: model.updates, version: model.version)
            }
        }
        .padding(20)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Secondary explanation under a setting, as in System Settings.
struct SettingNote: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            LabeledContent("Startup:") {
                Toggle(
                    "Open Dotwell at login",
                    isOn: Binding(get: { model.launchAtLogin }, set: { model.toggleLaunchAtLogin($0) }))
            }
            Spacer().frame(height: 8)
            Picker("Panel open:", selection: $settings.openInterval) {
                ForEach(SamplingInterval.whileOpen, id: \.self) { Text($0.label).tag($0) }
            }
            .fixedSize()
            SettingNote("Only while you're looking at it, so faster is fine.")
            Picker("Panel closed:", selection: $settings.closedInterval) {
                ForEach(SamplingInterval.whileClosed, id: \.self) { interval in
                    Text(interval == .fiveSeconds ? "\(interval.label) (recommended)" : interval.label).tag(interval)
                }
            }
            .fixedSize()
            SettingNote("Runs all day to keep the menu bar light current. Longer is easier on the battery.")
            Spacer().frame(height: 8)
            Picker("Show network speed in:", selection: $settings.networkUnit) {
                Text("Bits per second (Mbps)").tag(NetworkUnit.bits)
                Text("Bytes per second (MB/s)").tag(NetworkUnit.bytes)
            }
            .pickerStyle(.radioGroup)
            Spacer().frame(height: 8)
            Picker("Show app CPU use as:", selection: $settings.processCPUScale) {
                Text("Share of the whole Mac").tag(ProcessCPUScale.wholeMac)
                Text("Share of one core, like Activity Monitor").tag(ProcessCPUScale.perCore)
            }
            .pickerStyle(.radioGroup)
            SettingNote("With one core, an app busy on several cores can go over 100%.")
            Spacer().frame(height: 8)
            LabeledContent("IP addresses:") {
                Toggle("Show local and public IP addresses", isOn: $settings.showsIPAddresses)
            }
            SettingNote("Turn off before sharing your screen. When off, Dotwell never looks up your public address.")
        }
        .formStyle(.columns)
    }
}

// MARK: - Widgets

struct WidgetSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingNote("Choose which cards the popover shows. Drag them to change their order.")
            List {
                ForEach(settings.widgets) { widget in
                    WidgetRow(
                        module: widget.module,
                        isVisible: binding(widget.module, \.isVisible),
                        showsTopApp: binding(widget.module, \.showsTopApp))
                }
                .onMove { settings.moveWidgets(from: $0, to: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: CGFloat(settings.widgets.count) * 44 + 8)
            HStack {
                SettingNote("Top app shows the app using the most of that resource while the popover is open.")
                Spacer(minLength: 12)
                Button("Restore Defaults") { settings.restoreDefaultWidgets() }
            }
        }
    }

    private func binding(_ module: Module, _ key: WritableKeyPath<WidgetSetting, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.widgets.first { $0.module == module }?[keyPath: key] ?? true },
            set: { newValue in
                guard let index = settings.widgets.firstIndex(where: { $0.module == module }) else { return }
                settings.widgets[index][keyPath: key] = newValue
            })
    }
}

private struct WidgetRow: View {
    var module: Module
    @Binding var isVisible: Bool
    @Binding var showsTopApp: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            SymbolBadge(symbol: module.symbol, level: .ok)
                .opacity(isVisible ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.title)
                if let note = module.settingsNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if module.hasTopApp {
                Toggle("Top app", isOn: $showsTopApp)
                    .toggleStyle(.checkbox)
                    .disabled(!isVisible)
            }
            Toggle("Show \(module.title)", isOn: $isVisible)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

extension Module {
    /// When a card isn't always there, say so next to its switch.
    var settingsNote: String? {
        switch self {
        case .ping: return "Hidden with its alert off, Dotwell stops pinging"
        case .power: return "Only on Macs with a battery"
        case .thermal: return "Appears only while macOS slows the Mac down to cool it"
        default: return nil
        }
    }
}

// MARK: - Updates

struct UpdateSettingsView: View {
    var updates: UpdateSettings?
    var version: String

    var body: some View {
        Form {
            if let updates {
                UpdateControls(updates: updates)
            } else {
                LabeledContent("Updates:") {
                    SettingNote("This build can't update itself. New versions are on GitHub Releases.")
                }
            }
            Spacer().frame(height: 8)
            LabeledContent("Version:") {
                Text(version).textSelection(.enabled)
            }
        }
        .formStyle(.columns)
    }
}

private struct UpdateControls: View {
    @ObservedObject var updates: UpdateSettings

    var body: some View {
        LabeledContent("Automatic updates:") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Check for updates every day", isOn: $updates.automaticallyChecks)
                Toggle("Download and install them automatically", isOn: $updates.automaticallyDownloads)
                    .disabled(!updates.automaticallyChecks)
            }
        }
        Spacer().frame(height: 8)
        LabeledContent("Last checked:") {
            HStack(spacing: 12) {
                Text(lastCheckText).foregroundStyle(.secondary)
                Button("Check Now") {
                    updates.checkNow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { updates.refresh() }
                }
            }
        }
        .onAppear { updates.refresh() }
    }

    private var lastCheckText: String {
        guard let date = updates.lastCheck else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }
}
