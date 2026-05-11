import SwiftUI

struct TaskDetailSheet: View {
    let task: CadenceTask
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var editedTitle: String
    @State private var editedBody: String

    init(task: CadenceTask) {
        self.task = task
        _editedTitle = State(initialValue: task.title)
        _editedBody = State(initialValue: task.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: { store.toggle(task) }) {
                    HStack(spacing: 6) {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(task.isDone ? AppTheme.accent : AppTheme.textTertiary)
                        Text(task.isDone ? "Mark as To Do" : "Mark as Done")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    var updated = task
                    updated.title = editedTitle
                    updated.body = editedBody
                    store.update(updated)
                    dismiss()
                }) {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.accent))
                }
                .buttonStyle(.plain)

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AppTheme.divider))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider().background(AppTheme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    TextField("Task title", text: $editedTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .textFieldStyle(.plain)

                    // Body
                    TextEditor(text: $editedBody)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)

                    Divider().background(AppTheme.divider)

                    // Deadline info
                    DeadlineInfoSection(task: task, settings: settings)
                }
                .padding(24)
            }
        }
        .frame(width: 540, height: 460)
        .background(AppTheme.contentBackground)
    }
}

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
