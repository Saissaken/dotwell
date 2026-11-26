import AppKit
import MonitorCore
import SwiftUI

/// Local and public IP addresses under the Network module. Click an address to copy it.
struct AddressesView: View {
    var addresses: NetworkAddresses

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                AddressRow(
                    symbol: localSymbol, label: localLabel, value: addresses.local?.ipv4,
                    placeholder: "Not connected")
                AddressRow(
                    symbol: "globe", label: "Public", value: publicIPv4,
                    placeholder: publicPlaceholder)
            }
            if let ipv6 = addresses.publicAddresses?.ipv6 {
                AddressRow(symbol: "globe", label: "Public IPv6", value: ipv6, placeholder: "")
            }
        }
        .font(.caption)
    }

    /// With IPv6 only, the IPv6 row below already shows the public address.
    private var publicIPv4: String? { addresses.publicAddresses?.ipv4 }

    private var publicPlaceholder: String {
        if addresses.local == nil { return "—" }
        if addresses.isLoadingPublic && addresses.publicAddresses == nil { return "Looking up…" }
        if addresses.publicAddresses?.ipv6 != nil { return "No IPv4" }
        return "Unavailable"
    }

    private var localLabel: String {
        switch addresses.local?.kind {
        case .wifi: return "Wi‑Fi"
        case .ethernet: return "Ethernet"
        case .cellular: return "Cellular"
        case .vpn: return "VPN"
        case .other: return addresses.local?.interface ?? "Local"
        case nil: return "Local"
        }
    }

    private var localSymbol: String {
        switch addresses.local?.kind {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .vpn: return "lock.fill"
        case .other, nil: return "network"
        }
    }
}

private struct AddressRow: View {
    var symbol: String
    var label: String
    var value: String?
    var placeholder: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .accessibilityHidden(true)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let value {
                Button(action: { copy(value) }) {
                    Text(copied ? "Copied" : value)
                        .monospacedDigit()
                        .foregroundStyle(copied ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .textSelection(.disabled)
                }
                .buttonStyle(.plain)
                .help("Click to copy")
                .accessibilityLabel("\(label) address \(value)")
                .accessibilityHint("Copies the address")
            } else {
                Text(placeholder).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}
