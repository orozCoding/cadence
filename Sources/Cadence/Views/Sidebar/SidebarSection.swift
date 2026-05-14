import SwiftUI

struct SidebarSection<Content: View>: View {
    let label: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .pointerCursor()

            if isExpanded {
                content()
            }
        }
    }
}
