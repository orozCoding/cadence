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
    @State private var editedUrls: [String]
    @State private var validationErrors: [String] = []

    // Precomputed once so hasUnsavedChanges doesn't re-normalize stored URLs every render.
    private let normalizedStoredUrls: [String]

    // Debounced auto-save — cancelled and restarted on every change
    @State private var autoSaveTask: Task<Void, Never>? = nil

    // Guards against a second store.update() when onDisappear fires after goBack() already saved.
    @State private var didSaveOnBack = false

    @State private var bodyFocusTrigger = 0

    // Undo/redo history for title + body — immediate push on first burst keystroke,
    // then debounced 1s; capped at 50 snapshots
    @State private var history: [(title: String, body: String)] = []
    @State private var historyIndex: Int = 0
    @State private var historySnapshotTask: Task<Void, Never>? = nil
    @State private var editBurstActive = false

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
        _editedUrls  = State(initialValue: task.urls.isEmpty ? [""] : task.urls)
        _history     = State(initialValue: [(title: task.title, body: task.body)])
        normalizedStoredUrls = task.urls.map { normalizeURL($0) }.filter { !$0.isEmpty }
    }

    private var trimmedTitle: String { editedTitle.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedTitle.isEmpty }
    private var canUndo: Bool { historyIndex > 0 }
    private var canRedo: Bool { historyIndex < history.count - 1 }

    // Live version reflects any isDone toggles made while this view is open.
    private var currentTask: CadenceTask {
        store.tasks.first(where: { $0.id == task.id }) ?? task
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button(action: goBack) {
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

                HStack(spacing: 2) {
                    Button(action: performUndo) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12))
                            .foregroundStyle(canUndo ? AppTheme.textSecondary : AppTheme.textTertiary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .disabled(!canUndo)
                    .help("Undo")

                    Button(action: performRedo) {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 12))
                            .foregroundStyle(canRedo ? AppTheme.textSecondary : AppTheme.textTertiary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .disabled(!canRedo)
                    .help("Redo")
                }

                Spacer()

                Button(action: {
                    autoSaveTask?.cancel()
                    historySnapshotTask?.cancel()
                    save()
                }) {
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
            .frame(height: AppTheme.headerHeight)

            Divider().background(AppTheme.divider)

            // Title — fixed height, always at top
            TextField("Task title", text: $editedTitle)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .textFieldStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)

            // Body — fills all remaining space; ChecklistBodyEditor handles checkboxes and plain text
            ScrollView {
                ZStack(alignment: .topLeading) {
                    if editedBody.isEmpty {
                        Text("Add content… type [] for a checklist item")
                            .font(.system(size: 13).italic())
                            .foregroundStyle(AppTheme.textTertiary.opacity(0.7))
                            .allowsHitTesting(false)
                            .padding(.top, 2)
                    }
                    ChecklistBodyEditor(text: $editedBody, focusTrigger: bodyFocusTrigger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { bodyFocusTrigger += 1 }
                )
            }
            .frame(maxHeight: .infinity)

            Divider().background(AppTheme.divider)

            // URLs + Deadlines — anchored to bottom, always visible
            VStack(alignment: .leading, spacing: 16) {
                URLEditSection(urls: $editedUrls)
                    .onChange(of: editedUrls) { _, _ in scheduleAutoSave() }

                Divider().background(AppTheme.divider)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Deadlines")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)

                    DeadlineToggleRow(icon: "sun.max", label: "Day", isEnabled: $enableDay) {
                        let dayMin = task.dayDeadline.map { min($0, Date().startOfDay()) } ?? Date().startOfDay()
                        DatePicker("Day deadline", selection: $dayDate, in: dayMin..., displayedComponents: .date)
                            .labelsHidden()
                            .accessibilityLabel("Day deadline")
                            .onChange(of: dayDate) { cascadeFromDay(); scheduleAutoSave() }
                    }
                    .onChange(of: enableDay) { cascadeAll(); scheduleAutoSave() }

                    DeadlineToggleRow(icon: "calendar", label: "Week", isEnabled: $enableWeek) {
                        let weekMin = task.weekStart.map { min($0, Date().startOfWeek(weekStartsOn: settings.weekStartsOn)) } ?? Date().startOfWeek(weekStartsOn: settings.weekStartsOn)
                        DatePicker("Week deadline", selection: $weekDate,
                                   in: weekMin...,
                                   displayedComponents: .date)
                            .labelsHidden()
                            .onChange(of: weekDate) { cascadeFromWeek(); scheduleAutoSave() }
                    }
                    .onChange(of: enableWeek) { cascadeAll(); scheduleAutoSave() }

                    DeadlineToggleRow(icon: "calendar.badge.clock", label: "Month", isEnabled: $enableMonth) {
                        let monthMin = task.monthStart.map { min($0, Date().startOfMonth()) } ?? Date().startOfMonth()
                        DatePicker("Month deadline", selection: $monthDate,
                                   in: monthMin...,
                                   displayedComponents: .date)
                            .labelsHidden()
                            .onChange(of: monthDate) { cascadeFromMonth(); scheduleAutoSave() }
                    }
                    .onChange(of: enableMonth) { cascadeAll(); scheduleAutoSave() }

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
                        .onChange(of: yearValue) { scheduleAutoSave() }
                    }
                    .onChange(of: enableYear) { cascadeAll(); scheduleAutoSave() }

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
                }  // end inner Deadlines VStack
            }      // end outer URLs+Deadlines VStack
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(AppTheme.contentBackground)
        .onChange(of: editedTitle) { _, _ in
            scheduleAutoSave()
            scheduleHistorySnapshot()
        }
        .onChange(of: editedBody) { _, _ in
            scheduleAutoSave()
            scheduleHistorySnapshot()
        }
        .onDisappear {
            // Sidebar navigation bypasses the Back button — save immediately on disappear.
            // Skip if goBack() already saved to avoid a redundant store.update().
            autoSaveTask?.cancel()
            historySnapshotTask?.cancel()
            if !didSaveOnBack { saveNow() }
        }
    }

    // MARK: - Save

    // Auto-save: persists silently; falls back to latest persisted title if field is blank.
    // Skips deadline validation errors if the overdue deadline is unchanged.
    // Skips URL validation errors — invalid URLs are simply dropped on auto-save.
    private func saveNow() {
        let titleToSave = trimmedTitle.isEmpty ? currentTask.title : trimmedTitle
        let (newDay, newWeek, newMonth, newYear) = computeDeadlines()
        var errors = buildValidationErrors(day: newDay, week: newWeek, month: newMonth, year: newYear)
        stripPastErrors(from: &errors, day: newDay, week: newWeek, month: newMonth, year: newYear)

        // Auto-save persists only valid normalized URLs. Invalid/partial rows stay in editedUrls
        // SwiftUI state so the user can keep typing without losing the slot in the UI.
        let normalizedUrls = editedUrls.compactMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let normalized = normalizeURL(trimmed)
            return isSaveableURL(normalized) ? normalized : nil
        }

        var updated = currentTask
        updated.title = titleToSave
        updated.body  = editedBody
        if errors.isEmpty {
            validationErrors = []
            updated.dayDeadline  = newDay
            updated.weekStart    = newWeek
            updated.monthStart   = newMonth
            updated.yearDeadline = newYear
        }
        updated.urls = normalizedUrls
        store.update(updated)
    }

    // Explicit Save button: validates with UI feedback, saves and goes back.
    private func save() {
        let (newDay, newWeek, newMonth, newYear) = computeDeadlines()
        var errors = buildValidationErrors(day: newDay, week: newWeek, month: newMonth, year: newYear)
        stripPastErrors(from: &errors, day: newDay, week: newWeek, month: newMonth, year: newYear)
        // Report the user's original input in error messages, not the normalized form.
        errors += editedUrls.compactMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isSaveableURL(normalizeURL(trimmed)) else { return nil }
            return "Invalid URL: \(trimmed)"
        }
        validationErrors = errors
        guard errors.isEmpty else { return }
        let normalizedUrls = editedUrls.map { normalizeURL($0) }.filter { !$0.isEmpty }

        var updated = currentTask
        updated.title        = trimmedTitle
        updated.body         = editedBody
        updated.dayDeadline  = newDay
        updated.weekStart    = newWeek
        updated.monthStart   = newMonth
        updated.yearDeadline = newYear
        updated.urls         = normalizedUrls
        didSaveOnBack = true
        store.update(updated)
        onBack()
    }

    private func goBack() {
        autoSaveTask?.cancel()
        historySnapshotTask?.cancel()
        didSaveOnBack = true
        saveNow()
        onBack()
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                saveNow()
            } catch {}
        }
    }

    // MARK: - Deadline helpers

    private func computeDeadlines() -> (day: Date?, week: Date?, month: Date?, year: Int?) {
        let newDay = enableDay ? dayDate.noonLocal() : nil
        let newWeek: Date?
        if enableWeek {
            if let orig = task.weekStart, weekDate.isSameDay(as: orig) {
                newWeek = orig
            } else {
                newWeek = weekDate.startOfWeek(weekStartsOn: settings.weekStartsOn).noonLocal()
            }
        } else {
            newWeek = nil
        }
        let newMonth = enableMonth ? monthDate.startOfMonth().noonLocal() : nil
        let newYear  = enableYear  ? yearValue : nil
        return (newDay, newWeek, newMonth, newYear)
    }

    private func buildValidationErrors(day: Date?, week: Date?, month: Date?, year: Int?) -> [String] {
        CadenceTask.validate(
            day: day, weekStart: week, monthStart: month, year: year,
            weekStartsOn: settings.weekStartsOn
        )
    }

    private func stripPastErrors(from errors: inout [String], day: Date?, week: Date?, month: Date?, year: Int?) {
        if day   == task.dayDeadline  { errors.removeAll { $0 == "Day deadline cannot be in the past." } }
        if task.weekStart != nil && weekDate.isSameDay(as: task.weekStart!) { errors.removeAll { $0 == "Week deadline cannot be in the past." } }
        if month == task.monthStart   { errors.removeAll { $0 == "Month deadline cannot be in the past." } }
        if year  == task.yearDeadline { errors.removeAll { $0 == "Year deadline cannot be in the past." } }
    }

    // MARK: - Cascade

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

    // MARK: - History

    private func scheduleHistorySnapshot() {
        // Truncate redo and reset burst when state diverges from the history cursor
        // (typing after undo). After undo/redo the state matches the cursor, so this is
        // a no-op on the onChange fired by performUndo/performRedo themselves.
        let cursor = history[historyIndex]
        if (cursor.title != editedTitle || cursor.body != editedBody) && historyIndex < history.count - 1 {
            history = Array(history[0...historyIndex])
            editBurstActive = false
        }

        if !editBurstActive {
            editBurstActive = true
            pushSnapshot()
        }
        historySnapshotTask?.cancel()
        historySnapshotTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                editBurstActive = false
                pushSnapshot()
            } catch {}
        }
    }

    private func pushSnapshot() {
        let current = history[historyIndex]
        guard current.title != editedTitle || current.body != editedBody else { return }
        if historyIndex < history.count - 1 {
            history = Array(history[0...historyIndex])
        }
        history.append((title: editedTitle, body: editedBody))
        historyIndex = history.count - 1
        if history.count > 50 {
            history.removeFirst()
            historyIndex -= 1
        }
    }

    private func performUndo() {
        guard canUndo else { return }
        editBurstActive = true
        historyIndex -= 1
        let snap = history[historyIndex]
        editedTitle = snap.title
        editedBody = snap.body
    }

    private func performRedo() {
        guard canRedo else { return }
        editBurstActive = true
        historyIndex += 1
        let snap = history[historyIndex]
        editedTitle = snap.title
        editedBody = snap.body
    }
}
