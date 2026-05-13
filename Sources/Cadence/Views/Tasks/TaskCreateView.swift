import SwiftUI

struct TaskCreateView: View {
    let prefillSelection: NavSelection?
    let onBack: () -> Void

    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var folderStore: FolderStore

    @State private var title = ""
    @State private var body_ = ""
    @State private var enableDay = false
    @State private var enableWeek = false
    @State private var enableMonth = false
    @State private var enableYear = false
    @State private var dayDate = Date()
    @State private var weekDate = Date()
    @State private var monthDate = Date()
    @State private var yearValue = Calendar.current.component(.year, from: Date())
    @State private var validationErrors: [String] = []

    // Guards against duplicate store.add() calls when both an explicit save path
    // (goBack / save button) and .onDisappear both fire in the same session.
    @State private var taskSaved = false

    // Undo/redo history for title + body — immediate push on first burst keystroke,
    // then debounced 1s; capped at 50 snapshots
    @State private var history: [(title: String, body: String)] = [("", "")]
    @State private var historyIndex: Int = 0
    @State private var historySnapshotTask: Task<Void, Never>? = nil
    @State private var editBurstActive = false

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canUndo: Bool { historyIndex > 0 }
    private var canRedo: Bool { historyIndex < history.count - 1 }

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

                Text("New Task")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

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

                Button(action: save) {
                    Text("Add Task")
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

            // Title — fixed height, always at top
            TextField("Task title", text: $title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .textFieldStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .onChange(of: title) { _, _ in scheduleHistorySnapshot() }

            // Body — fills all remaining space
            ZStack(alignment: .topLeading) {
                if body_.isEmpty {
                    Text("Add content...")
                        .font(.system(size: 13).italic())
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.7))
                        .allowsHitTesting(false)
                        .padding(.top, 2)
                        .padding(.leading, 28)
                }
                TextEditor(text: $body_)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 20)
                    .onChange(of: body_) { _, _ in scheduleHistorySnapshot() }
            }
            .frame(maxHeight: .infinity)

            Divider().background(AppTheme.divider)

            // Deadlines — anchored to bottom, always visible
            VStack(alignment: .leading, spacing: 12) {
                Text("Deadlines")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)

                DeadlineToggleRow(icon: "sun.max", label: "Day", isEnabled: $enableDay) {
                    DatePicker("Day deadline", selection: $dayDate, in: Date().startOfDay()..., displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel("Day deadline")
                        .onChange(of: dayDate) { cascadeFromDay() }
                }
                .onChange(of: enableDay) { cascadeAll() }

                DeadlineToggleRow(icon: "calendar", label: "Week", isEnabled: $enableWeek) {
                    DatePicker("Week deadline", selection: $weekDate,
                               in: Date().startOfWeek(weekStartsOn: settings.weekStartsOn)...,
                               displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: weekDate) { cascadeFromWeek() }
                }
                .onChange(of: enableWeek) { cascadeAll() }

                DeadlineToggleRow(icon: "calendar.badge.clock", label: "Month", isEnabled: $enableMonth) {
                    DatePicker("Month deadline", selection: $monthDate,
                               in: Date().startOfMonth()...,
                               displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: monthDate) { cascadeFromMonth() }
                }
                .onChange(of: enableMonth) { cascadeAll() }

                DeadlineToggleRow(icon: "archivebox", label: "Year", isEnabled: $enableYear) {
                    Picker("Year deadline", selection: $yearValue) {
                        ForEach((Calendar.current.component(.year, from: Date()))...(Calendar.current.component(.year, from: Date()) + 10), id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Year deadline")
                    .frame(width: 90)
                }
                .onChange(of: enableYear) { cascadeAll() }

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
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(AppTheme.contentBackground)
        .onAppear { prefill() }
        .onDisappear {
            // Sidebar navigation bypasses Back — auto-save if title is filled.
            historySnapshotTask?.cancel()
            saveIfPossible()
        }
    }

    // MARK: - Navigation

    // Back button: auto-save if title is filled, then go back.
    // Explicit discard is gone — the Back button is now the "close without explicit save" path.
    private func goBack() {
        historySnapshotTask?.cancel()
        saveIfPossible()
        onBack()
    }

    // Save the draft if title is non-empty and deadline validation passes.
    // The taskSaved flag prevents a second store.add() when onDisappear fires
    // after goBack() or save() have already persisted the task.
    private func saveIfPossible() {
        guard !taskSaved, canSave else { return }
        let errors = CadenceTask.validate(
            day: enableDay ? dayDate.noonLocal() : nil,
            weekStart: enableWeek ? weekDate.startOfWeek(weekStartsOn: settings.weekStartsOn).noonLocal() : nil,
            monthStart: enableMonth ? monthDate.startOfMonth() : nil,
            year: enableYear ? yearValue : nil,
            weekStartsOn: settings.weekStartsOn
        )
        guard errors.isEmpty else { return }
        taskSaved = true
        let task = CadenceTask(
            folderId: folderStore.activeFolder.id,
            title: title.trimmingCharacters(in: .whitespaces),
            body: body_,
            dayDeadline: enableDay ? dayDate.noonLocal() : nil,
            weekStart: enableWeek ? weekDate.startOfWeek(weekStartsOn: settings.weekStartsOn).noonLocal() : nil,
            monthStart: enableMonth ? monthDate.startOfMonth().noonLocal() : nil,
            yearDeadline: enableYear ? yearValue : nil
        )
        store.add(task)
    }

    // MARK: - Explicit save (Add Task button)

    private func save() {
        let errors = CadenceTask.validate(
            day: enableDay ? dayDate.noonLocal() : nil,
            weekStart: enableWeek ? weekDate.startOfWeek(weekStartsOn: settings.weekStartsOn).noonLocal() : nil,
            monthStart: enableMonth ? monthDate.startOfMonth() : nil,
            year: enableYear ? yearValue : nil,
            weekStartsOn: settings.weekStartsOn
        )
        validationErrors = errors
        guard errors.isEmpty else { return }
        taskSaved = true
        let task = CadenceTask(
            folderId: folderStore.activeFolder.id,
            title: title.trimmingCharacters(in: .whitespaces),
            body: body_,
            dayDeadline: enableDay ? dayDate.noonLocal() : nil,
            weekStart: enableWeek ? weekDate.startOfWeek(weekStartsOn: settings.weekStartsOn).noonLocal() : nil,
            monthStart: enableMonth ? monthDate.startOfMonth().noonLocal() : nil,
            yearDeadline: enableYear ? yearValue : nil
        )
        store.add(task)
        onBack()
    }

    // MARK: - History

    private func scheduleHistorySnapshot() {
        let cursor = history[historyIndex]
        if (cursor.title != title || cursor.body != body_) && historyIndex < history.count - 1 {
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
        guard current.title != title || current.body != body_ else { return }
        if historyIndex < history.count - 1 {
            history = Array(history[0...historyIndex])
        }
        history.append((title: title, body: body_))
        if history.count > 50 { history.removeFirst() }
        historyIndex = history.count - 1
    }

    private func performUndo() {
        guard canUndo else { return }
        editBurstActive = true
        historyIndex -= 1
        let snap = history[historyIndex]
        title = snap.title
        body_ = snap.body
    }

    private func performRedo() {
        guard canRedo else { return }
        editBurstActive = true
        historyIndex += 1
        let snap = history[historyIndex]
        title = snap.title
        body_ = snap.body
    }

    // MARK: - Prefill / Cascade

    private func prefill() {
        let now = Date()
        let currentYear = Calendar.current.component(.year, from: now)
        switch prefillSelection {
        case .day(let d):
            enableDay = true
            dayDate = d < now.startOfDay() ? now : d
        case .week(let s):
            enableWeek = true
            let minWeek = now.startOfWeek(weekStartsOn: settings.weekStartsOn)
            weekDate = s < minWeek ? minWeek : s
        case .month(let s):
            enableMonth = true
            let minMonth = now.startOfMonth()
            monthDate = s < minMonth ? minMonth : s
        case .year(let y):
            enableYear = true
            yearValue = y < currentYear ? currentYear : y
        default: break
        }
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
}
