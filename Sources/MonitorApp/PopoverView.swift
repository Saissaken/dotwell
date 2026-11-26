import SwiftUI

/// Placeholder popover content; real metrics arrive in the next increments.
struct PopoverView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mac Resource Monitor")
                .font(.headline)
            Text("Todo en orden")
                .foregroundStyle(.secondary)
            Divider()
            HStack {
                Spacer()
                Button("Salir") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
