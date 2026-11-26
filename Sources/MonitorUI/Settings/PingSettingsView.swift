import MonitorCore
import SwiftUI

/// A few well-chosen hosts: your network, the internet, and two cloud regions you pick.
struct PingSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            LabeledContent("Your network:") {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Router, ISP and DNS")
                    SettingNote(
                        "Found automatically: your Wi-Fi or Ethernet router, the first router of your internet "
                            + "provider, and the DNS server your Mac uses to look up names.")
                }
            }
            Spacer().frame(height: 8)
            Picker("Internet:", selection: $settings.internetHost) {
                ForEach(InternetHost.allCases, id: \.self) { host in
                    Text("\(host.target.name) (\(host.target.host))").tag(host)
                }
            }
            .fixedSize()
            SettingNote(
                "Answered by the nearest server of a global network, so it shows how fast the internet is "
                    + "from here.")
            Spacer().frame(height: 8)
            ForEach(0..<PingSlot.regionCount, id: \.self) { index in
                RegionPicker(index: index, settings: settings)
            }
            SettingNote(
                "Compare the cloud regions you use. Clouds ignore ping, so Dotwell times how long a connection "
                    + "takes to open, or for Google Cloud, how long a small request takes.")
            Spacer().frame(height: 8)
            Picker("Status light follows:", selection: $settings.primarySlot) {
                ForEach(settings.pingSlots, id: \.slot) { row in
                    Text(row.target.name).tag(row.slot)
                }
            }
            .fixedSize()
            SettingNote("The menu bar light turns yellow or red when this host is slow or drops replies.")
            HStack {
                Spacer()
                Button("Restore Defaults") { settings.restoreDefaultTargets() }
            }
            .padding(.top, 8)
        }
        .formStyle(.columns)
    }
}

/// Provider and region for one regional slot.
private struct RegionPicker: View {
    var index: Int
    @ObservedObject var settings: AppSettings

    private var region: CloudRegion? { settings.regions.indices.contains(index) ? settings.regions[index] : nil }

    var body: some View {
        LabeledContent("Region \(index + 1):") {
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
        }
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
