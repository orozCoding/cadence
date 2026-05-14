import SwiftUI

// MARK: - Toggle row (used by NewTaskSheet)

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

// MARK: - Display row (used by TaskDetailSheet)

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

// MARK: - Section (used by TaskDetailSheet)

struct DeadlineInfoSection: View {
    let task: CadenceTask
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deadlines")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)

            if let d = task.dayDeadline {
                DeadlineRow(icon: "sun.max", label: "Day", value: d.dayLabel())
            }
            if let w = task.weekStart {
                DeadlineRow(icon: "calendar", label: "Week", value: w.weekLabel(weekStartsOn: settings.weekStartsOn))
            }
            if let m = task.monthStart {
                DeadlineRow(icon: "calendar.badge.clock", label: "Month", value: m.monthLabel())
            }
            if let y = task.yearDeadline {
                DeadlineRow(icon: "archivebox", label: "Year", value: String(y))
            }
        }
    }
}
