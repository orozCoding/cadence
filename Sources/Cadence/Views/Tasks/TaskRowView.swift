import SwiftUI

struct TaskRowView: View {
    let task: CadenceTask
    let onTap: () -> Void
    let onToggle: () -> Void

    @EnvironmentObject var settings: AppSettings
    @State private var isHovered = false

    private var accessibilityLabel: String {
        var parts = [task.title]
        if let day = task.dayDeadline {
            parts.append("due \(day.dayLabel())")
        } else if let week = task.weekStart {
            parts.append("due \(week.weekLabel(weekStartsOn: settings.weekStartsOn))")
        } else if let month = task.monthStart {
            parts.append("due \(month.monthLabel())")
        } else if let year = task.yearDeadline {
            parts.append("due \(year)")
        }
        if task.isDone { parts.append("completed") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(task.isDone ? AppTheme.accent : AppTheme.textTertiary)
                    .animation(.easeInOut(duration: 0.15), value: task.isDone)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.isDone ? AppTheme.doneText : AppTheme.textPrimary)
                    .strikethrough(task.isDone, color: AppTheme.doneText)

                if !task.body.isEmpty {
                    Text(task.body)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            deadlineBadges
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .fill(isHovered ? AppTheme.hoveredItem : AppTheme.cardBackground)
        )
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onTap)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(task.body.isEmpty ? "Open details" : task.body)
        .accessibilityAction(.default, onTap)
        .accessibilityAction(named: task.isDone ? "Mark as To Do" : "Mark as Done", onToggle)
    }

    @ViewBuilder
    private var deadlineBadges: some View {
        if let day = task.dayDeadline {
            DeadlineBadge(label: day.dayLabel(), color: AppTheme.accentLight)
        } else if let week = task.weekStart {
            DeadlineBadge(label: week.weekLabel(weekStartsOn: settings.weekStartsOn), color: AppTheme.accentLight)
        } else if let month = task.monthStart {
            DeadlineBadge(label: month.monthLabel(), color: AppTheme.accentLight)
        } else if let year = task.yearDeadline {
            DeadlineBadge(label: String(year), color: AppTheme.accentLight)
        }
    }
}

struct DeadlineBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.12))
            )
    }
}
