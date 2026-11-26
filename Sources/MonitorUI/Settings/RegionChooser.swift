import MonitorCore
import SwiftUI

/// Measures a provider's regions while the chooser is open.
@MainActor
final class RegionLatencyModel: ObservableObject {
    @Published var readings: [String: RegionLatency.Reading]
    private var probe: RegionLatency?
    /// False for previews and tests, which show fixed readings.
    private let isLive: Bool

    init(readings: [String: RegionLatency.Reading]? = nil) {
        self.readings = readings ?? [:]
        isLive = readings == nil
    }

    func measure(_ provider: CloudProvider) {
        guard isLive else { return }
        probe?.stop()
        readings = [:]
        let probe = RegionLatency(regions: CloudRegion.regions(of: provider))
        probe.onUpdate = { [weak self] readings in
            Task { @MainActor in self?.readings = readings }
        }
        self.probe = probe
        probe.start()
    }

    func stop() {
        probe?.stop()
        probe = nil
    }

    func reading(_ region: CloudRegion) -> RegionLatency.Reading {
        readings[region.id] ?? .measuring
    }

    /// Fastest first; regions still measuring next, then those that didn't answer. Ties keep the catalog order.
    func sorted(_ regions: [CloudRegion]) -> [CloudRegion] {
        func rank(_ region: CloudRegion) -> (Int, Float) {
            switch reading(region) {
            case .milliseconds(let ms): return (0, ms)
            case .measuring: return (1, 0)
            case .noAnswer: return (2, 0)
            }
        }
        return regions.enumerated().sorted { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            return ra != rb ? ra < rb : a.offset < b.offset
        }
        .map(\.element)
    }
}

/// Picks the cloud region for one ping row, showing how far each one is from this Mac right now.
struct RegionChooser: View {
    var index: Int
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var latency: RegionLatencyModel
    @State private var provider: CloudProvider
    @State private var selection: CloudRegion?

    /// Pass `latency` to show fixed readings (previews); by default the chooser measures while it is open.
    init(index: Int, settings: AppSettings, latency: RegionLatencyModel? = nil) {
        self.index = index
        self.settings = settings
        _latency = StateObject(wrappedValue: latency ?? RegionLatencyModel())
        let current = settings.regions.indices.contains(index) ? settings.regions[index] : nil
        _provider = State(initialValue: current?.provider ?? .aws)
        _selection = State(initialValue: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Region \(index + 1)").font(.headline)
            Picker("Provider", selection: $provider) {
                ForEach(CloudProvider.allCases, id: \.self) { Text($0.longTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            List(latency.sorted(CloudRegion.regions(of: provider)), selection: $selection) { region in
                HStack(spacing: 8) {
                    Text(region.city)
                    Text(region.code).font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    ReadingLabel(reading: latency.reading(region))
                }
                .tag(region)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(height: 300)
            Text(
                "Measured from this Mac right now, fastest first, the same way as in the panel. Dotwell only "
                    + "measures while this window is open."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Turn Off") {
                    settings.setRegion(nil, at: index)
                    dismiss()
                }
                .help("Removes this row from the Ping card.")
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Choose") {
                    settings.setRegion(selection, at: index)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection?.provider != provider)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { latency.measure(provider) }
        .onChange(of: provider) { latency.measure($0) }
        .onDisappear { latency.stop() }
    }
}

private struct ReadingLabel: View {
    var reading: RegionLatency.Reading

    var body: some View {
        switch reading {
        case .measuring:
            HStack(spacing: 4) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Measuring").font(.callout).foregroundStyle(.secondary)
            }
        case .milliseconds(let ms):
            HStack(spacing: 5) {
                Circle().fill(color(ms)).frame(width: 7, height: 7).accessibilityHidden(true)
                Text("\(Int(ms.rounded())) ms").monospacedDigit()
            }
        case .noAnswer:
            Text("No answer").font(.callout).foregroundStyle(.secondary)
        }
    }

    /// The default ping alert limits: green below 80 ms, yellow up to 200 ms, red above.
    private func color(_ ms: Float) -> Color { ms < 80 ? .green : ms < 200 ? .orange : .red }
}

extension CloudProvider {
    var longTitle: String {
        switch self {
        case .aws: return "AWS"
        case .gcp: return "Google Cloud"
        case .azure: return "Azure"
        }
    }
}
