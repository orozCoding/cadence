import SwiftUI

struct NewTaskSheet: View {
    let prefillSelection: NavSelection?
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

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

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("New Task")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
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
                        }
                        .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.sidebarBackground))
                    }

                    // Deadlines
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deadlines")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)

                        // Day
                        DeadlineToggleRow(
                            icon: "sun.max", label: "Day",
                            isEnabled: $enableDay
                        ) {
                            DatePicker("", selection: $dayDate, in: Date()..., displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: dayDate) { cascadeFromDay() }
                        }

                        // Week
                        DeadlineToggleRow(
                            icon: "calendar", label: "Week",
                            isEnabled: $enableWeek
                        ) {
                            DatePicker("Week deadline", selection: $weekDate, displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: weekDate) { cascadeFromWeek() }
                        }
                        .onChange(of: enableWeek) { _, on in if on { cascadeFromDay() } }

                        // Month
                        DeadlineToggleRow(
                            icon: "calendar.badge.clock", label: "Month",
                            isEnabled: $enableMonth
                        ) {
                            DatePicker("Month deadline", selection: $monthDate, displayedComponents: .date)
                                .labelsHidden()
                                .onChange(of: monthDate) { cascadeFromMonth() }
                        }
                        .onChange(of: enableMonth) { _, on in if on { cascadeFromWeek() } }

                        // Year
                        DeadlineToggleRow(
                            icon: "archivebox", label: "Year",
                            isEnabled: $enableYear
                        ) {
                            Picker("Year deadline", selection: $yearValue) {
                                ForEach((Calendar.current.component(.year, from: Date()))...(Calendar.current.component(.year, from: Date()) + 10), id: \.self) { y in
                                    Text(String(y)).tag(y)
                                }
                            }
                            .labelsHidden()
                            .accessibilityLabel("Year deadline")
                            .frame(width: 90)
                        }
                        .onChange(of: enableYear) { _, on in if on { cascadeFromMonth() } }
                    }

                    // Validation errors
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

            Divider().background(AppTheme.divider)

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)

                Button(action: save) {
                    Text("Add Task")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(canSave ? AppTheme.accent : AppTheme.textTertiary))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 480)
        .background(AppTheme.contentBackground)
        .onAppear { prefill() }
    }

    // MARK: - Logic

    private func prefill() {
        switch prefillSelection {
        case .day(let d):
            enableDay = true; dayDate = d
        case .week(let s):
            enableWeek = true; weekDate = s
        case .month(let s):
            enableMonth = true; monthDate = s
        case .year(let y):
            enableYear = true; yearValue = y
        default: break
        }
    }

    private func cascadeFromDay() {
        // If week is enabled, ensure it's not before the day's week
        if enableWeek {
            let dayWeek = dayDate.startOfWeek(weekStartsOn: settings.weekStartsOn)
            if weekDate < dayWeek { weekDate = dayWeek }
        }
        cascadeFromWeek()
    }

    private func cascadeFromWeek() {
        if enableMonth {
            let weekMonth = weekDate.startOfMonth()
            if monthDate < weekMonth { monthDate = weekMonth }
        }
        cascadeFromMonth()
    }

    private func cascadeFromMonth() {
        if enableYear {
            let monthYear = Calendar.current.component(.year, from: monthDate)
            if yearValue < monthYear { yearValue = monthYear }
        }
    }

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
            title: title.trimmingCharacters(in: .whitespaces),
            body: body_,
            dayDeadline: enableDay ? dayDate.noonLocal() : nil,
            weekStart: enableWeek ? weekDate.startOfWeek(weekStartsOn: settings.weekStartsOn).noonLocal() : nil,
            monthStart: enableMonth ? monthDate.startOfMonth().noonLocal() : nil,
            yearDeadline: enableYear ? yearValue : nil
        )
        store.add(task)
        dismiss()
    }
}

// MARK: - Helper

struct DeadlineToggleRow<Content: View>: View {
    let icon: String
    let label: String
    @Binding var isEnabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Toggle(label, isOn: $isEnabled)
                .labelsHidden()
                .accessibilityLabel("\(label) deadline")
                .toggleStyle(.switch)
                .controlSize(.small)

            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? AppTheme.accent : AppTheme.textTertiary)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(isEnabled ? AppTheme.textPrimary : AppTheme.textTertiary)

            Spacer()

            if isEnabled {
                content()
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isEnabled)
    }
}
