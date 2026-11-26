import SwiftUI

/// The rounded, colored icon tile of System Settings' sidebar and page headers.
struct SettingsIcon: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(tint.gradient)
            )
            .accessibilityHidden(true)
    }
}

/// The first section of a page: a large icon, the page's name and what it is about, like the top of
/// System Settings' Siri or Wi-Fi pages. A widget page also has the switch that shows its card.
struct PageHeader<Accessory: View>: View {
    var page: SettingsPage
    var summary: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: page.symbol, tint: page.tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title).font(.headline)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(.vertical, 4)
    }
}

extension PageHeader where Accessory == EmptyView {
    init(page: SettingsPage, summary: String) {
        self.init(page: page, summary: summary) { EmptyView() }
    }
}

/// A setting's name with the line under it that says what it does. Every setting also has a tooltip,
/// added with `.help(_:)` where it is used.
struct SettingLabel: View {
    var title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A switch row: the name and its explanation on the left, the switch on the right.
struct SwitchRow: View {
    var title: String
    var detail: String?
    var help: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { SettingLabel(title, detail: detail) }
            .toggleStyle(.switch)
            .help(help)
    }
}

/// A yellow or red limit: the level's dot, a short number field with a stepper, and the unit.
struct LimitField: View {
    var color: Color
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var unit: String

    var body: some View {
        let clamped = Binding(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) })
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            TextField("", value: clamped, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .labelsHidden()
            Stepper("", value: clamped, in: range, step: step)
                .labelsHidden()
            Text(unit).foregroundStyle(.secondary).frame(minWidth: 22, alignment: .leading)
        }
        .fixedSize()
    }
}

/// Opens a web page in the default browser.
struct WebLink: View {
    var title: String
    var url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "arrow.up.forward.square").imageScale(.small)
            }
        }
        .help(url.absoluteString)
    }
}

/// Where Dotwell lives on the web.
public enum DotwellLinks {
    // Literal URLs are valid, so the unwraps can't fail.
    public static let website = URL(string: "https://saissaken.github.io/dotwell/") ?? URL(fileURLWithPath: "/")
    public static let source = URL(string: "https://github.com/Saissaken/dotwell") ?? URL(fileURLWithPath: "/")
}
