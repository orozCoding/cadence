import SwiftUI

struct DeadlineToggleRow<Content: View>: View {
    let icon: String
    let label: String
    @Binding var isEnabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Toggle(label, isOn: $isEnabled)
                .labelsHidden()
                .accessibilityLabel("\(label) deadline")
                .toggleStyle(.switch)
                .controlSize(.small)

            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? AppTheme.accent : AppTheme.textTertiary)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? AppTheme.textPrimary : AppTheme.textTertiary)

            Spacer()

            if isEnabled {
                content()
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isEnabled)
    }
}
