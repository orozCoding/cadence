import SwiftUI

struct DeadlineRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}
