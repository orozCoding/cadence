import SwiftUI

struct TaskDetailSheet: View {
    let task: CadenceTask
    let onDismiss: () -> Void
    @Binding var backdropTap: Bool

    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings

    @State private var editedTitle: String
    @State private var editedBody: String
    @State private var showDiscardAlert = false

    init(task: CadenceTask, onDismiss: @escaping () -> Void, backdropTap: Binding<Bool>) {
        self.task = task
        self.onDismiss = onDismiss
        self._backdropTap = backdropTap
        _editedTitle = State(initialValue: task.title)
        _editedBody = State(initialValue: task.body)
    }

    private var trimmedTitle: String { editedTitle.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedTitle.isEmpty }
    private var hasUnsavedChanges: Bool {
        trimmedTitle != task.title || editedBody != task.body
    }

    // Live version of the task from the store (reflects any isDone toggles).
    private var currentTask: CadenceTask {
        store.tasks.first(where: { $0.id == task.id }) ?? task
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button(action: { store.toggle(task) }) {
                    HStack(spacing: 6) {
                        Image(systemName: currentTask.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(currentTask.isDone ? AppTheme.accent : AppTheme.textTertiary)
                        Text(currentTask.isDone ? "Mark as To Do" : "Mark as Done")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .pointerCursor()

                Spacer()

                Button(action: {
                    var updated = currentTask
                    updated.title = trimmedTitle
                    updated.body = editedBody
                    store.update(updated)
                    onDismiss()
                }) {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(canSave ? AppTheme.accent : AppTheme.textTertiary))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(!canSave)

                Button(action: tryDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AppTheme.divider))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider().background(AppTheme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Task title", text: $editedTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .textFieldStyle(.plain)

                    TextEditor(text: $editedBody)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)

                    Divider().background(AppTheme.divider)

                    DeadlineInfoSection(task: task, settings: settings)
                }
                .padding(24)
            }
        }
        .frame(width: 540, height: 460)
        .background(AppTheme.contentBackground)
        .onChange(of: backdropTap) { _, tapped in
            if tapped { backdropTap = false; tryDismiss() }
        }
        .confirmationDialog("Discard unsaved changes?", isPresented: $showDiscardAlert, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { onDismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    private func tryDismiss() {
        if hasUnsavedChanges { showDiscardAlert = true } else { onDismiss() }
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

            let today = settings.currentDate
            if let d = task.dayDeadline {
                DeadlineRow(icon: "sun.max", label: "Day", value: d.dayLabel(today: today))
            }
            if let w = task.weekStart {
                DeadlineRow(icon: "calendar", label: "Week", value: w.weekLabel(weekStartsOn: settings.weekStartsOn, today: today))
            }
            if let m = task.monthStart {
                DeadlineRow(icon: "calendar.badge.clock", label: "Month", value: m.monthLabel(today: today))
            }
            if let y = task.yearDeadline {
                DeadlineRow(icon: "archivebox", label: "Year", value: y.yearLabel(today: today))
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
