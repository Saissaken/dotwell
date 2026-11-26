import MonitorCore
import SwiftUI

/// A few well-chosen hosts: your network, the internet, and two cloud regions you pick.
struct PingSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        let alerts = AlertBindings(settings: settings)
        Section {
            LabeledContent {
                Text("Found automatically").foregroundStyle(.secondary)
            } label: {
                SettingLabel(
                    "Router and ISP", detail: "Your Wi-Fi or Ethernet router, then your provider's first router.")
            }
            .help(
                "Dotwell finds your router from the Mac's network settings, and your provider's first router with a "
                    + "short trace. They follow you when you change networks.")
            LabeledContent {
                Text("Found automatically").foregroundStyle(.secondary)
            } label: {
                SettingLabel("DNS", detail: "The server your Mac uses to look up names.")
            }
            .help("Every 5 seconds Dotwell asks your DNS server for www.apple.com and times the answer.")
            Picker(selection: $settings.internetHost) {
                ForEach(InternetHost.allCases, id: \.self) { host in
                    Text("\(host.target.name) (\(host.target.host))").tag(host)
                }
            } label: {
                SettingLabel("Internet", detail: "Answered by the closest server of a global network.")
            }
            .help(
                "These networks answer from a server near you, so this shows how fast the internet is from here, "
                    + "not how far away one website is.")
            ForEach(0..<PingSlot.regionCount, id: \.self) { index in
                RegionRow(index: index, settings: settings)
            }
        } header: {
            Text("Hosts")
        } footer: {
            Footer(
                "Clouds ignore ping, so for regions Dotwell times how long a connection takes to open "
                    + "(for Google Cloud, a small request).")
        }
        Section {
            Picker(selection: $settings.primarySlot) {
                ForEach(settings.pingSlots, id: \.slot) { row in
                    Text(row.target.name).tag(row.slot)
                }
            } label: {
                SettingLabel("Main host", detail: "Shown big at the top of the card, with the route to it.")
            }
            .help(
                "The main host is the large number at the top of the Ping card, the one Dotwell traces router by "
                    + "router, and the one whose alert colors the menu bar light.")
        }
        Section {
            SwitchRow(
                title: "Alert when ping is slow or drops replies",
                detail: nil,
                help: "Turns the menu bar light yellow or red when the main host goes over these limits.",
                isOn: alerts.isOn(.ping))
            LimitsRow(
                title: "Latency above",
                help: "Average round trip over the last 10 seconds. Yellow above the first limit, red above the "
                    + "second.",
                warning: alerts.limit(\.pingWarningMs, partner: \.pingCriticalMs, isLower: true),
                critical: alerts.limit(\.pingCriticalMs, partner: \.pingWarningMs, isLower: false),
                range: 1...2000, step: 10, unit: "ms"
            )
            .disabled(!settings.alerts.contains(.ping))
            LimitsRow(
                title: "Packet loss above",
                help: "Share of probes with no answer over the last 10 seconds.",
                warning: alerts.limit(\.pingLossWarning, partner: \.pingLossCritical, isLower: true, scale: 100),
                critical: alerts.limit(\.pingLossCritical, partner: \.pingLossWarning, isLower: false, scale: 100),
                range: 1...100, step: 1, unit: "%"
            )
            .disabled(!settings.alerts.contains(.ping))
        } header: {
            Text("Alert")
        } footer: {
            Footer("Applies to the main host. The light changes after 3 seconds over a limit.")
        }
        Section {
            HStack {
                Spacer()
                Button("Restore Defaults") { settings.restoreDefaultTargets() }
                    .help("Cloudflare, AWS São Paulo and AWS Virginia, with Cloudflare as the main host.")
            }
        }
    }
}

/// Provider and region for one regional slot.
private struct RegionRow: View {
    var index: Int
    @ObservedObject var settings: AppSettings

    private var region: CloudRegion? { settings.regions.indices.contains(index) ? settings.regions[index] : nil }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Picker("Provider", selection: provider) {
                    ForEach(CloudProvider.allCases, id: \.self) { Text($0.title).tag(CloudProvider?.some($0)) }
                    Divider()
                    Text("Off").tag(CloudProvider?.none)
                }
                .labelsHidden()
                .fixedSize()
                if let region {
                    Picker("Region", selection: regionBinding) {
                        ForEach(CloudRegion.regions(of: region.provider)) { option in
                            Text("\(option.city) (\(option.code))").tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        } label: {
            Text("Region \(index + 1)")
        }
        .help("A cloud region you use, to compare how far it is. Choose Off to hide this row.")
    }

    /// Switching provider keeps the closest match: the same city if the new provider has it.
    private var provider: Binding<CloudProvider?> {
        Binding(
            get: { region?.provider },
            set: { newProvider in
                guard let newProvider else { return settings.setRegion(nil, at: index) }
                guard newProvider != region?.provider else { return }
                let options = CloudRegion.regions(of: newProvider)
                let sameCity = options.first { $0.city == region?.city }
                settings.setRegion(sameCity ?? options.first, at: index)
            })
    }

    private var regionBinding: Binding<CloudRegion> {
        Binding(
            get: { region ?? CloudRegion.defaultFirst },
            set: { settings.setRegion($0, at: index) })
    }
}
