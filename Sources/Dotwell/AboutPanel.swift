import AppKit
import MonitorUI

/// The standard About panel, with a link to the website under the version.
@MainActor
final class AboutPanel: NSObject {
    static let shared = AboutPanel()

    @objc func show(_ sender: Any?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: "saissaken.github.io/dotwell",
            attributes: [
                .link: DotwellLinks.website,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .paragraphStyle: paragraph,
            ])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
