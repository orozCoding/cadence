import SwiftUI
import AppKit

extension View {
    func pointerCursor() -> some View {
        self.onHover { hovering in
            hovering ? NSCursor.pointingHand.push() : NSCursor.pop()
        }
    }
}
