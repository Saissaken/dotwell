import MonitorCore
import SwiftUI

struct PingSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var selection: Set<Int> = []
    @State private var editing: TargetEdit?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Status light follows:", selection: $settings.primaryTargetIndex) {
                ForEach(settings.pingTargets.indices, id: \.self) { index in
                    Text(settings.pingTargets[index].name).tag(index)
                }
            }
            .fixedSize()
            SettingNote(
                "The menu bar light turns yellow or red when this host is slow or drops replies. "
                    + "The other hosts are shown for comparison.")
            List(selection: $selection) {
                ForEach(Array(settings.pingTargets.enumerated()), id: \.offset) { index, target in
                    TargetRow(target: target, isPrimary: index == settings.primaryTargetIndex)
                        .tag(index)
                }
                .onMove { settings.moveTargets(from: $0, to: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 230)
            .contextMenu(forSelectionType: Int.self) { indices in
                if indices.count == 1, let index = indices.first {
                    Button("Edit…") { edit(index) }
                    Button("Use for Status Light") { settings.primaryTargetIndex = index }
                }
                Button("Remove") { remove(indices) }
                    .disabled(settings.pingTargets.count - indices.count < 1)
            } primaryAction: { indices in
                if indices.count == 1, let index = indices.first { edit(index) }
            }
            controls
        }
        .sheet(item: $editing) { edit in
            TargetEditor(edit: edit) { target in
                if let index = edit.index {
                    settings.replaceTarget(at: index, with: target)
                } else {
                    settings.addTarget(target)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Menu("Add") { presets }
                .fixedSize()
                .disabled(!settings.canAddTarget)
            Button("Remove") { remove(selection) }
                .disabled(selection.isEmpty || settings.pingTargets.count - selection.count < 1)
            Button("Edit…") { selection.first.map(edit) }
                .disabled(selection.count != 1)
            Text("\(settings.pingTargets.count) of \(PingTarget.maximumCount)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button("Restore Defaults") {
                selection.removeAll()
                settings.restoreDefaultTargets()
            }
        }
    }

    @ViewBuilder
    private var presets: some View {
        ForEach(PingTarget.presets, id: \.name) { group in
            Menu(group.name) {
                ForEach(group.targets, id: \.self) { target in
                    Button(target.name) { settings.addTarget(target) }
                        .disabled(settings.pingTargets.contains(target))
                }
            }
        }
        Divider()
        Button("Custom Host…") { editing = TargetEdit(index: nil, target: nil) }
    }

    private func edit(_ index: Int) {
        guard settings.pingTargets.indices.contains(index) else { return }
        editing = TargetEdit(index: index, target: settings.pingTargets[index])
    }

    private func remove(_ indices: Set<Int>) {
        settings.removeTargets(at: IndexSet(indices))
        selection.removeAll()
    }
}

private struct TargetRow: View {
    var target: PingTarget
    var isPrimary: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(target.name)
                Text(target.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isPrimary {
                Label("Status light", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(StatusLightLabelStyle())
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct StatusLightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(.green).imageScale(.small)
            configuration.title
        }
    }
}

extension PingTarget {
    /// Host and method, as shown under the name.
    var detail: String {
        let host = isGateway ? "Your router, found automatically" : host
        switch method {
        case .icmp: return host
        case .tcp(let port): return "\(host) · TCP port \(port)"
        }
    }
}

/// What the editor sheet is editing: an existing target, or a new one when `index` is nil.
struct TargetEdit: Identifiable {
    let id = UUID()
    var index: Int?
    var target: PingTarget?
}

private struct TargetEditor: View {
    let edit: TargetEdit
    let onSave: (PingTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var host: String
    @State private var usesTCP: Bool
    @State private var port: Int

    init(edit: TargetEdit, onSave: @escaping (PingTarget) -> Void) {
        self.edit = edit
        self.onSave = onSave
        let target = edit.target
        _name = State(initialValue: target?.name ?? "")
        _host = State(initialValue: target?.host ?? "")
        if case .tcp(let port) = target?.method {
            _usesTCP = State(initialValue: true)
            _port = State(initialValue: Int(port))
        } else {
            _usesTCP = State(initialValue: false)
            _port = State(initialValue: 443)
        }
    }

    private var isGateway: Bool { edit.target?.isGateway == true }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }

    private var isValid: Bool {
        !trimmedName.isEmpty && (isGateway || PingTarget.isValidHost(trimmedHost))
            && (!usesTCP || (1...65535).contains(port))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(edit.index == nil ? "Add a Host" : "Edit Host").font(.headline)
            Form {
                TextField("Name:", text: $name, prompt: Text("Office VPN"))
                if isGateway {
                    LabeledContent("Host:") { Text("Your router, found automatically") }
                } else {
                    TextField("Host:", text: $host, prompt: Text("1.1.1.1 or example.com"))
                }
                Picker("Measure with:", selection: $usesTCP) {
                    Text("Ping (ICMP echo)").tag(false)
                    Text("TCP connection").tag(true)
                }
                .pickerStyle(.radioGroup)
                if usesTCP {
                    TextField("Port:", value: $port, format: .number.grouping(.never))
                        .frame(width: 140)
                }
            }
            .formStyle(.columns)
            SettingNote(
                "Some hosts, like AWS, ignore ping. For those, Dotwell times how long a TCP connection takes "
                    + "to open on the port you choose, usually 443.")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(edit.index == nil ? "Add" : "Save") {
                    let method: PingTarget.Method = usesTCP ? .tcp(port: UInt16(port)) : .icmp
                    let host = isGateway ? PingTarget.gatewayHost : trimmedHost
                    onSave(PingTarget(name: trimmedName, host: host, method: method))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
