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
    @State private var showDiscardAlert = false
    @State private var userHasInteracted = false

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasDraft: Bool {
        userHasInteracted && (!title.isEmpty || !body_.isEmpty || enableDay || enableWeek || enableMonth || enableYear)
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

                Text("New Task")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Title", systemImage: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                        TextField("What needs to be done?", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.sidebarBackground))
                            .onChange(of: title) { userHasInteracted = true }
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Description", systemImage: "text.alignleft")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                        ZStack(alignment: .topLeading) {
                            if body_.isEmpty {
                                Text("Add more detail...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textTertiary)
                                    .padding(.top, 10)
                                    .padding(.leading, 11)
                            }
                            TextEditor(text: $body_)
                                .font(.system(size: 13))
                                .frame(minHeight: 80)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .onChange(of: body_) { userHasInteracted = true }
                        }
                        .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.sidebarBackground))
                    }

                    // Deadlines
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deadlines")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)

                        DeadlineToggleRow(icon: "sun.max", label: "Day", isEnabled: $enableDay) {
                            DatePicker("Day deadline", selection: $dayDate, in: Date().startOfDay()..., displayedComponents: .date)
                                .labelsHidden()
                                .accessibilityLabel("Day deadline")
                                .onChange(of: dayDate) { userHasInteracted = true; cascadeFromDay() }
                        }
                        .onChange(of: enableDay) { userHasInteracted = true; cascadeAll() }

                        DeadlineToggleRow(icon: "calendar", label: "Week", isEnabled: $enableWeek) {
                            DatePicker("Week deadline", selection: $weekDate,
                                       in: Date().startOfWeek(weekStartsOn: settings.weekStartsOn)...,
                                       displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: weekDate) { userHasInteracted = true; cascadeFromWeek() }
                        }
                        .onChange(of: enableWeek) { userHasInteracted = true; cascadeAll() }

                        DeadlineToggleRow(icon: "calendar.badge.clock", label: "Month", isEnabled: $enableMonth) {
                            DatePicker("Month deadline", selection: $monthDate,
                                       in: Date().startOfMonth()...,
                                       displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: monthDate) { userHasInteracted = true; cascadeFromMonth() }
                        }
                        .onChange(of: enableMonth) { userHasInteracted = true; cascadeAll() }

                        DeadlineToggleRow(icon: "archivebox", label: "Year", isEnabled: $enableYear) {
                            Picker("Year deadline", selection: $yearValue) {
                                ForEach((Calendar.current.component(.year, from: Date()))...(Calendar.current.component(.year, from: Date()) + 10), id: \.self) { y in
                                    Text(String(y)).tag(y)
                                }
                            }
                            .labelsHidden()
                            .accessibilityLabel("Year deadline")
                            .frame(width: 90)
                            .onChange(of: yearValue) { userHasInteracted = true }
                        }
                        .onChange(of: enableYear) { userHasInteracted = true; cascadeAll() }
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
        .onAppear { prefill() }
        .confirmationDialog("Discard this draft?", isPresented: $showDiscardAlert, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { onBack() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    // MARK: - Logic

    private func tryBack() {
        if hasDraft { showDiscardAlert = true } else { onBack() }
    }

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
}
