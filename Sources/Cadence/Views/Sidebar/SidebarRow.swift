import SwiftUI

struct SidebarRow: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AppTheme.accentDark : AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(isSelected ? AppTheme.selectedItem : (isHovered ? AppTheme.hoveredItem : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }
}
