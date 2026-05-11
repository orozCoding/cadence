import SwiftUI

struct TaskEditView: View {
    let task: CadenceTask
    let onBack: () -> Void

    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings

    @State private var editedTitle: String
    @State private var editedBody: String
    @State private var enableDay: Bool
    @State private var enableWeek: Bool
    @State private var enableMonth: Bool
    @State private var enableYear: Bool
    @State private var dayDate: Date
    @State private var weekDate: Date
    @State private var monthDate: Date
    @State private var yearValue: Int
    @State private var validationErrors: [String] = []
    @State private var showDiscardAlert = false

    init(task: CadenceTask, onBack: @escaping () -> Void) {
        self.task = task
        self.onBack = onBack
        _editedTitle = State(initialValue: task.title)
        _editedBody  = State(initialValue: task.body)
        _enableDay   = State(initialValue: task.dayDeadline != nil)
        _enableWeek  = State(initialValue: task.weekStart != nil)
        _enableMonth = State(initialValue: task.monthStart != nil)
        _enableYear  = State(initialValue: task.yearDeadline != nil)
        _dayDate     = State(initialValue: task.dayDeadline ?? Date())
        _weekDate    = State(initialValue: task.weekStart ?? Date())
        _monthDate   = State(initialValue: task.monthStart ?? Date())
        _yearValue   = State(initialValue: task.yearDeadline ?? Calendar.current.component(.year, from: Date()))
    }

    private var trimmedTitle: String { editedTitle.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedTitle.isEmpty }

    // Live version reflects any isDone toggles made while this view is open.
    private var currentTask: CadenceTask {
        store.tasks.first(where: { $0.id == task.id }) ?? task
    }

    private var hasUnsavedChanges: Bool {
        if trimmedTitle != task.title || editedBody != task.body { return true }
        if enableDay != (task.dayDeadline != nil) { return true }
        if enableWeek != (task.weekStart != nil) { return true }
        if enableMonth != (task.monthStart != nil) { return true }
        if enableYear != (task.yearDeadline != nil) { return true }
        if enableDay, let orig = task.dayDeadline, !dayDate.isSameDay(as: orig) { return true }
        if enableWeek, let orig = task.weekStart,
           weekDate.startOfWeek(weekStartsOn: settings.weekStartsOn).noonLocal() != orig { return true }
        if enableMonth, let orig = task.monthStart,
           monthDate.startOfMonth().noonLocal() != orig { return true }
        if enableYear, yearValue != task.yearDeadline { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: tryBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                        Text("Back")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .pointerCursor()

                Spacer()

                Button(action: { store.toggle(task) }) {
                    HStack(spacing: 6) {
                        Image(systemName: currentTask.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(currentTask.isDone ? AppTheme.accent : AppTheme.textTertiary)
                        Text(currentTask.isDone ? "Mark as To Do" : "Mark as Done")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .pointerCursor()

                Spacer()

                Button(action: save) {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(canSave ? AppTheme.accent : AppTheme.textTertiary))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(!canSave)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider().background(AppTheme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title (large, editable)
                    TextField("Task title", text: $editedTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .textFieldStyle(.plain)

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Description", systemImage: "text.alignleft")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                        ZStack(alignment: .topLeading) {
                            if editedBody.isEmpty {
                                Text("Add more detail...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .padding(.top, 10)
                                    .padding(.leading, 11)
                            }
                            TextEditor(text: $editedBody)
                                .font(.system(size: 13))
                                .frame(minHeight: 80)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                        }
                        .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.sidebarBackground))
                    }

                    Divider().background(AppTheme.divider)

                    // Deadlines
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deadlines")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)

                        DeadlineToggleRow(icon: "sun.max", label: "Day", isEnabled: $enableDay) {
                            // Allow keeping an existing overdue date; new picks are bounded to today.
                            let dayMin = task.dayDeadline.map { min($0, Date().startOfDay()) } ?? Date().startOfDay()
                            DatePicker("Day deadline", selection: $dayDate, in: dayMin..., displayedComponents: .date)
                                .labelsHidden()
                                .accessibilityLabel("Day deadline")
                                .onChange(of: dayDate) { cascadeFromDay() }
                        }
                        .onChange(of: enableDay) { cascadeAll() }

                        DeadlineToggleRow(icon: "calendar", label: "Week", isEnabled: $enableWeek) {
                            let weekMin = task.weekStart.map { min($0, Date().startOfWeek(weekStartsOn: settings.weekStartsOn)) } ?? Date().startOfWeek(weekStartsOn: settings.weekStartsOn)
                            DatePicker("Week deadline", selection: $weekDate,
                                       in: weekMin...,
                                       displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: weekDate) { cascadeFromWeek() }
                        }
                        .onChange(of: enableWeek) { cascadeAll() }

                        DeadlineToggleRow(icon: "calendar.badge.clock", label: "Month", isEnabled: $enableMonth) {
                            let monthMin = task.monthStart.map { min($0, Date().startOfMonth()) } ?? Date().startOfMonth()
                            DatePicker("Month deadline", selection: $monthDate,
                                       in: monthMin...,
                                       displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: monthDate) { cascadeFromMonth() }
                        }
                        .onChange(of: enableMonth) { cascadeAll() }

                        DeadlineToggleRow(icon: "archivebox", label: "Year", isEnabled: $enableYear) {
                            let yearMin = task.yearDeadline.map { min($0, Calendar.current.component(.year, from: Date())) } ?? Calendar.current.component(.year, from: Date())
                            Picker("Year deadline", selection: $yearValue) {
                                ForEach(yearMin...(yearMin + 10), id: \.self) { y in
                                    Text(String(y)).tag(y)
                                }
                            }
                            .labelsHidden()
                            .accessibilityLabel("Year deadline")
                            .frame(width: 90)
                        }
                        .onChange(of: enableYear) { cascadeAll() }
                    }

                    if !validationErrors.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(validationErrors, id: \.self) { err in
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.destructive)
                                    Text(err)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.destructive)
                                }
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.destructive.opacity(0.08)))
                    }
                }
                .padding(24)
            }
        }
        .background(AppTheme.contentBackground)
        .confirmationDialog("Discard unsaved changes?", isPresented: $showDiscardAlert, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { onBack() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    // MARK: - Logic

    private func tryBack() {
        if hasUnsavedChanges { showDiscardAlert = true } else { onBack() }
    }

    private func cascadeAll() {
        let cal = Calendar.current
        if enableDay && enableWeek {
            let dayWeek = dayDate.startOfWeek(weekStartsOn: settings.weekStartsOn)
            if weekDate < dayWeek { weekDate = dayWeek }
        }
        if enableMonth {
            let normalizedWeek = weekDate.startOfWeek(weekStartsOn: settings.weekStartsOn)
            let reference: Date? = enableWeek ? normalizedWeek : (enableDay ? dayDate : nil)
            if let ref = reference {
                let refMonth = ref.startOfMonth()
                if monthDate < refMonth { monthDate = refMonth }
            }
        }
        if enableYear {
            let normalizedWeek = weekDate.startOfWeek(weekStartsOn: settings.weekStartsOn)
            let refYear: Int
            if enableMonth { refYear = cal.component(.year, from: monthDate) }
            else if enableWeek { refYear = cal.component(.year, from: normalizedWeek) }
            else if enableDay { refYear = cal.component(.year, from: dayDate) }
            else { refYear = cal.component(.year, from: Date()) }
            if yearValue < refYear { yearValue = refYear }
        }
    }

    private func cascadeFromDay()   { cascadeAll() }
    private func cascadeFromWeek()  { cascadeAll() }
    private func cascadeFromMonth() { cascadeAll() }

    private func save() {
        let newDay   = enableDay   ? dayDate.noonLocal() : nil
        let newWeek  = enableWeek  ? weekDate.startOfWeek(weekStartsOn: settings.weekStartsOn).noonLocal() : nil
        let newMonth = enableMonth ? monthDate.startOfMonth().noonLocal() : nil
        let newYear  = enableYear  ? yearValue : nil

        // Skip the "not in past" check for deadlines that are unchanged from the original
        // so that overdue tasks remain editable without forced rescheduling.
        let errors = CadenceTask.validate(
            day:        newDay   == task.dayDeadline ? nil : newDay,
            weekStart:  newWeek  == task.weekStart   ? nil : newWeek,
            monthStart: newMonth == task.monthStart  ? nil : newMonth,
            year:       newYear  == task.yearDeadline ? nil : newYear,
            weekStartsOn: settings.weekStartsOn
        )
        validationErrors = errors
        guard errors.isEmpty else { return }

        var updated = currentTask
        updated.title = trimmedTitle
        updated.body = editedBody
        updated.dayDeadline  = newDay
        updated.weekStart    = newWeek
        updated.monthStart   = newMonth
        updated.yearDeadline = newYear
        store.update(updated)
        onBack()
    }
}
