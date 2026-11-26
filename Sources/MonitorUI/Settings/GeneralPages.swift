import AppKit
import MonitorCore
import SwiftUI

// MARK: - General

struct GeneralPage: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                PageHeader(page: .general, summary: "When Dotwell starts and how often it takes readings.")
            }
            Section {
                SwitchRow(
                    title: "Open Dotwell at login",
                    detail: nil,
                    help: "Starts Dotwell in the menu bar when you log in to this Mac.",
                    isOn: Binding(get: { model.launchAtLogin }, set: { model.toggleLaunchAtLogin($0) }))
            }
            Section {
                Picker(selection: $settings.openInterval) {
                    ForEach(SamplingInterval.whileOpen, id: \.self) { Text($0.label).tag($0) }
                } label: {
                    SettingLabel(
                        "While the panel is open", detail: "Only while you're looking at it, so faster is fine.")
                }
                .help(
                    "How often the panel's numbers and charts update while it's open. "
                        + "0.5 seconds is the smoothest; it stops as soon as you close the panel.")
                Picker(selection: $settings.closedInterval) {
                    ForEach(SamplingInterval.whileClosed, id: \.self) { interval in
                        Text(interval == .fiveSeconds ? "\(interval.label) (recommended)" : interval.label)
                            .tag(interval)
                    }
                } label: {
                    SettingLabel("While the panel is closed", detail: closedDetail)
                }
                .help(
                    "Dotwell keeps measuring in the background so the menu bar light can warn you. "
                        + "This runs all day, so it matters most for battery life.")
            } header: {
                Text("Update Readings")
            } footer: {
                Footer("Charts keep the same time scale and alerts the same timing, whatever you choose.")
            }
            Section {
                LabeledContent {
                    WebLink(title: "saissaken.github.io/dotwell", url: DotwellLinks.website)
                } label: {
                    SettingLabel("Website", detail: "News, help and the source code.")
                }
            }
        }
        .formStyle(.grouped)
    }

    /// What the closed interval costs and buys, in plain words.
    private var closedDetail: String {
        switch settings.closedInterval {
        case .halfSecond, .oneSecond:
            return "Highest energy use. The menu bar light reacts within a second or two."
        case .twoSeconds:
            return "Low energy use. The light reacts to a problem within about 3 seconds."
        case .fiveSeconds:
            return "Very low energy use. The light reacts to a problem within about 5 seconds."
        case .tenSeconds:
            return "Lowest energy use. The light reacts to a problem within about 10 seconds."
        case .thirtySeconds:
            return "Least energy. The light can take up to 30 seconds to react."
        }
    }
}

// MARK: - Updates

struct UpdatesPage: View {
    var updates: UpdateSettings?
    var version: String

    var body: some View {
        Form {
            Section {
                PageHeader(page: .updates, summary: "Dotwell updates itself from GitHub Releases, signed and verified.")
            }
            if let updates {
                UpdateControls(updates: updates)
            } else {
                Section {
                    LabeledContent("Updates") {
                        Text("This build can't update itself.").foregroundStyle(.secondary)
                    }
                    .help("Builds made with `swift run` or from source don't include the updater.")
                }
            }
            Section {
                LabeledContent("Version") { Text(version).textSelection(.enabled) }
                LabeledContent {
                    WebLink(title: "Release notes", url: DotwellLinks.source.appendingPathComponent("releases"))
                } label: {
                    Text("What's new")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdateControls: View {
    @ObservedObject var updates: UpdateSettings

    var body: some View {
        Section {
            SwitchRow(
                title: "Check for updates automatically",
                detail: "Once a day.",
                help: "Asks GitHub once a day whether a newer Dotwell is out. Nothing else is sent.",
                isOn: $updates.automaticallyChecks)
            SwitchRow(
                title: "Download and install updates automatically",
                detail: "They're installed the next time Dotwell quits.",
                help: "Downloads new versions in the background and installs them when Dotwell next quits.",
                isOn: $updates.automaticallyDownloads
            )
            .disabled(!updates.automaticallyChecks)
            LabeledContent {
                HStack(spacing: 10) {
                    Text(lastCheckText).foregroundStyle(.secondary)
                    Button("Check Now") {
                        updates.checkNow()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { updates.refresh() }
                    }
                    .help("Looks for a new version right now.")
                }
            } label: {
                Text("Last checked")
            }
        }
        .onAppear { updates.refresh() }
    }

    private var lastCheckText: String {
        guard let date = updates.lastCheck else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }
}

// MARK: - About

struct AboutPage: View {
    var version: String

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    Text("Dotwell").font(.title2.weight(.semibold))
                    Text("Version \(version)").foregroundStyle(.secondary).textSelection(.enabled)
                    Text("A tiny menu bar monitor for your Mac's health, built to stay out of the way.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                LabeledContent("Website") {
                    WebLink(title: "saissaken.github.io/dotwell", url: DotwellLinks.website)
                }
                LabeledContent("Source code") {
                    WebLink(title: "github.com/Saissaken/dotwell", url: DotwellLinks.source)
                }
                LabeledContent("License") { Text("MIT").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}
