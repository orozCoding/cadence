import SwiftUI
import AppKit

extension View {
    func pointerCursor() -> some View {
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}
