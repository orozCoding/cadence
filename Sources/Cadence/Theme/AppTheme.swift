import SwiftUI

enum AppTheme {
    // MARK: - Colors
    static let sidebarBackground = Color(hex: "#E8F4FD")
    static let contentBackground = Color(hex: "#F7FBFF")
    static let panelBackground = Color(hex: "#EBF5FB")
    static let accent = Color(hex: "#2B8FD4")
    static let accentLight = Color(hex: "#5AAEE0")
    static let accentDark = Color(hex: "#1A6FA8")
    static let textPrimary = Color(hex: "#1A2D3D")
    static let textSecondary = Color(hex: "#5A7A8C")
    static let textTertiary = Color(hex: "#8BAAB8")
    static let divider = Color(hex: "#C8DFF0")
    static let selectedItem = Color(hex: "#D0EAF8")
    static let hoveredItem = Color(hex: "#DCF0FC")
    static let doneText = Color(hex: "#8BAAB8")
    static let cardBackground = Color.white
    static let destructive = Color(hex: "#D94040")

    // MARK: - Dimensions
    static let sidebarWidth: CGFloat = 220
    static let timerPanelWidth: CGFloat = 260
    static let cornerRadius: CGFloat = 8
    static let rowHeight: CGFloat = 44
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
