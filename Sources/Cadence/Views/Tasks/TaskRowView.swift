import SwiftUI

struct TaskRowView: View {
    let task: CadenceTask
    let onTap: () -> Void
    let onToggle: () -> Void

    @EnvironmentObject var settings: AppSettings
    @State private var isHovered = false

    private var accessibilityLabel: String {
        var parts = [task.title]
        let today = settings.currentDate
        if let day = task.dayDeadline {
            parts.append("due \(day.dayLabel(today: today))")
        } else if let week = task.weekStart {
            parts.append("due \(week.weekLabel(weekStartsOn: settings.weekStartsOn, today: today))")
        } else if let month = task.monthStart {
            parts.append("due \(month.monthLabel(today: today))")
        } else if let year = task.yearDeadline {
            parts.append("due \(year.yearLabel(today: today))")
        }
        if task.isDone { parts.append("completed") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 10) {
            // Toggle button
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(task.isDone ? AppTheme.accent : AppTheme.textTertiary)
                    .animation(.easeInOut(duration: 0.2), value: task.isDone)
            }
            .buttonStyle(.plain)
            .pointerCursor()

            // Title + body
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: task.isDone ? .regular : .medium))
                    .foregroundStyle(task.isDone ? AppTheme.textTertiary : AppTheme.textPrimary)
                    .strikethrough(task.isDone, color: AppTheme.textTertiary)
                    .animation(.easeInOut(duration: 0.2), value: task.isDone)

                if !task.body.isEmpty {
                    Text(task.body)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            deadlineBadges

            urlBadges
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .fill(isHovered ? AppTheme.hoveredItem : AppTheme.cardBackground)
        )
        // Fade the whole row when done
        .opacity(task.isDone ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.25), value: task.isDone)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onTap)
        .pointerCursor()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(task.body.isEmpty ? "Open details" : task.body)
        .accessibilityAction(.default, onTap)
        .accessibilityAction(named: task.isDone ? "Mark as To Do" : "Mark as Done", onToggle)
    }

    @ViewBuilder
    private var urlBadges: some View {
        let validUrls = Array(task.urls.filter { !$0.isEmpty })
        if !validUrls.isEmpty {
            HStack(spacing: 3) {
                ForEach(Array(validUrls.prefix(5).enumerated()), id: \.offset) { _, url in
                    URLBadgeIcon(url: url)
                }
                if validUrls.count > 5 {
                    Text("+\(validUrls.count - 5)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.divider.opacity(0.5)))
                }
            }
        }
    }

    @ViewBuilder
    private var deadlineBadges: some View {
        let today = settings.currentDate
        if let day = task.dayDeadline {
            DeadlineBadge(label: day.dayLabel(today: today), color: task.isDone ? AppTheme.textTertiary : AppTheme.accentLight)
        } else if let week = task.weekStart {
            DeadlineBadge(label: week.weekLabel(weekStartsOn: settings.weekStartsOn, today: today), color: task.isDone ? AppTheme.textTertiary : AppTheme.accentLight)
        } else if let month = task.monthStart {
            DeadlineBadge(label: month.monthLabel(today: today), color: task.isDone ? AppTheme.textTertiary : AppTheme.accentLight)
        } else if let year = task.yearDeadline {
            DeadlineBadge(label: year.yearLabel(today: today), color: task.isDone ? AppTheme.textTertiary : AppTheme.accentLight)
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
