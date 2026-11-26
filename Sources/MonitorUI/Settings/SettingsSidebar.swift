import AppKit
import MonitorCore
import SwiftUI

/// The sidebar: a search field, General, one row per card in the popover's order (drag to reorder the
/// popover), then Updates and About.
struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $navigation.query, prompt: "Search")
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            List(selection: selection) {
                if SettingsPage.general.matches(navigation.query) {
                    Section { row(.general) }
                }
                let widgets = settings.widgets.map(\.module).filter {
                    SettingsPage.widget($0).matches(navigation.query)
                }
                if !widgets.isEmpty {
                    Section {
                        ForEach(widgets, id: \.self) { module in
                            row(.widget(module))
                                .help("Drag to change where the \(module.settingsTitle) card sits in the panel.")
                        }
                        .onMove(perform: navigation.query.isEmpty ? move : nil)
                    } header: {
                        Text("Widgets")
                    }
                }
                let rest = [SettingsPage.updates, .about].filter { $0.matches(navigation.query) }
                if !rest.isEmpty {
                    Section { ForEach(rest, id: \.self) { row($0) } }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if nothingMatches {
                    Text("No Results").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var nothingMatches: Bool {
        let pages: [SettingsPage] = [.general, .updates, .about] + settings.widgets.map { .widget($0.module) }
        return !pages.contains { $0.matches(navigation.query) }
    }

    private var selection: Binding<SettingsPage?> {
        Binding(
            get: { navigation.page },
            set: { if let page = $0 { navigation.show(page) } })
    }

    private func row(_ page: SettingsPage) -> some View {
        Label {
            Text(page.title)
        } icon: {
            SettingsIcon(symbol: page.symbol, tint: page.tint)
        }
        .tag(page)
        .opacity(isHidden(page) ? 0.5 : 1)
    }

    /// Hidden cards are dimmed, so the sidebar doubles as an overview of the popover.
    private func isHidden(_ page: SettingsPage) -> Bool {
        if case .widget(let module) = page { return !settings.isVisible(module) }
        return false
    }

    private func move(from source: IndexSet, to destination: Int) {
        settings.moveWidgets(from: source, to: destination)
    }
}

/// AppKit's search field, which SwiftUI on macOS 13 can only place in a toolbar.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.controlSize = .large
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// The page on the right.
struct SettingsDetail: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var model: SettingsModel

    var body: some View {
        Group {
            switch navigation.page {
            case .general: GeneralPage(model: model, settings: model.settings)
            case .widget(let module): WidgetPage(module: module, settings: model.settings, navigation: navigation)
            case .updates: UpdatesPage(updates: model.updates, version: model.version)
            case .about: AboutPage(version: model.version)
            }
        }
        .id(navigation.page)  // each page starts scrolled to the top
    }
}
