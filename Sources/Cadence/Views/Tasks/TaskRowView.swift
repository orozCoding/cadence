import SwiftUI

struct TaskRowView: View {
    let task: CadenceTask
    let onTap: () -> Void
    let onToggle: () -> Void

    @State private var isHovered = false

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
    }

    @ViewBuilder
    private var deadlineBadges: some View {
        HStack(spacing: 4) {
            if let day = task.dayDeadline {
                DeadlineBadge(label: day.dayLabel(), color: AppTheme.accentLight)
            }
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
