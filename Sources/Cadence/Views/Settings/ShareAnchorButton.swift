import SwiftUI
import AppKit

/// A SwiftUI button that exposes an underlying `NSView` to its action so
/// `NSSharingServicePicker` can anchor the share popover to it. Without a
/// real `NSView` the picker either fails to display or lands at an unhelpful
/// screen location.
struct ShareAnchorButton: View {
    let title: String
    let systemImage: String
    var isPrimary: Bool = false
    let action: (NSView?) -> Void

    @State private var anchor: NSView?

    var body: some View {
        styledButton
            .pointerCursor()
            .background(AnchorCapture(anchor: $anchor))
    }

    @ViewBuilder
    private var styledButton: some View {
        if isPrimary {
            Button {
                action(anchor)
            } label: {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                action(anchor)
            } label: {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Captures the nearest `NSView` so callers can hand it to AppKit APIs that
/// require a real view anchor (e.g. `NSSharingServicePicker.show`).
private struct AnchorCapture: NSViewRepresentable {
    @Binding var anchor: NSView?

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { anchor = v }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
