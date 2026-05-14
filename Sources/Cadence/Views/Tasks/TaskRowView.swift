import SwiftUI

struct TaskRowView: View {
    let task: CadenceTask
    let onTap: () -> Void
    let onToggle: () -> Void

    @EnvironmentObject var settings: AppSettings
    @State private var isHovered = false

    private var bodyPreview: String {
        task.body.components(separatedBy: "\n").compactMap { line -> String? in
            if line.hasPrefix("- [ ] ") { let t = String(line.dropFirst(6)); return t.isEmpty ? nil : t }
            if line.lowercased().hasPrefix("- [x] ") { let t = String(line.dropFirst(6)); return t.isEmpty ? nil : t }
            return line.isEmpty ? nil : line
        }.joined(separator: " · ")
    }

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
        if let progress = task.checklistProgress {
            parts.append("\(progress.completed) of \(progress.total) checklist items complete")
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

                if !bodyPreview.isEmpty {
                    Text(bodyPreview)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let progress = task.checklistProgress {
                ChecklistProgressBadge(completed: progress.completed, total: progress.total)
            }

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(bodyPreview.isEmpty ? "Open details" : bodyPreview)
        .accessibilityAction(.default, onTap)
        .accessibilityAction(named: task.isDone ? "Mark as To Do" : "Mark as Done", onToggle)
    }

    @ViewBuilder
    private var urlBadges: some View {
        // URLs are normalized at save time; URL(string:) check is sufficient here.
        let validUrls = task.urls.filter { !$0.isEmpty && URL(string: $0) != nil }
        if !validUrls.isEmpty {
            HStack(spacing: 3) {
                ForEach(Array(validUrls.prefix(5).enumerated()), id: \.offset) { _, url in
                    URLBadgeIcon(url: url)
                }
                if validUrls.count > 5 {
                    URLOverflowBadge(urls: Array(validUrls.dropFirst(5)))
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

struct ChecklistProgressBadge: View {
    let completed: Int
    let total: Int

    private var isComplete: Bool { completed == total }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checklist")
                .font(.system(size: 9, weight: .medium))
            Text("\(completed)/\(total)")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(isComplete ? AppTheme.accent : AppTheme.textTertiary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isComplete ? AppTheme.accent.opacity(0.12) : AppTheme.divider)
        )
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
