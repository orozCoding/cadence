import SwiftUI

struct FocusTimeView: View {
    @ObservedObject private var focusStore = FocusTimeStore.shared
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Focus Time")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: AppTheme.headerHeight)

            Divider().background(AppTheme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Summary cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        FocusSummaryCard(label: "Today",      seconds: focusStore.todaySeconds())
                        FocusSummaryCard(label: "This Week",  seconds: focusStore.weekSeconds(weekStartsOn: settings.weekStartsOn))
                        FocusSummaryCard(label: "This Month", seconds: focusStore.monthSeconds())
                        FocusSummaryCard(label: "This Year",  seconds: focusStore.yearSeconds())
                    }

                    // Daily log
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Daily Log")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)

                        let days = focusStore.sortedDays()
                        if days.isEmpty {
                            Text("No focus time recorded yet.")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.textTertiary)
                                .padding(.top, 4)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(days.enumerated()), id: \.element.key) { idx, entry in
                                    FocusDayRow(dayKey: entry.key, seconds: entry.seconds)
                                    if idx < days.count - 1 {
                                        Divider()
                                            .background(AppTheme.divider)
                                            .padding(.leading, 14)
                                    }
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.sidebarBackground))
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(AppTheme.contentBackground)
    }
}

// MARK: - Summary card

private struct FocusSummaryCard: View {
    let label: String
    let seconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)
            Text(formatFocusTime(seconds))
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(seconds > 0 ? AppTheme.textPrimary : AppTheme.textTertiary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.sidebarBackground))
    }
}

// MARK: - Day row (editable)

struct FocusDayRow: View {
    let dayKey: String
    let seconds: Int

    @State private var isEditing = false
    @State private var editBuffer = ""
    @State private var editError = false
    @State private var displaySeconds: Int? = nil  // optimistic value after a commit

    private var label: String { FocusTimeStore.shared.labelFor(key: dayKey) }
    private var shownSeconds: Int { displaySeconds ?? seconds }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(dayKey)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            if isEditing {
                HStack(spacing: 4) {
                    TextField("", text: $editBuffer)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(editError ? AppTheme.destructive : AppTheme.textPrimary)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { commitEdit() }
                        .onChange(of: editBuffer) { editError = false }
                    Text("s")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                    Button(action: commitEdit) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    Button(action: { isEditing = false; editError = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            } else {
                Button(action: startEditing) {
                    Text(formatFocusTime(shownSeconds))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityLabel("\(label): \(formatFocusTime(shownSeconds)). Click to edit.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onChange(of: seconds) { _, _ in
            // Store updated the value externally (e.g. timer tick) — drop optimistic override
            displaySeconds = nil
        }
    }

    private func startEditing() {
        editBuffer = "\(shownSeconds)"
        editError = false
        isEditing = true
    }

    private func commitEdit() {
        guard let newSecs = Int(editBuffer), newSecs >= 0 else { editError = true; return }
        displaySeconds = newSecs  // show immediately; store update triggers re-render shortly after
        FocusTimeStore.shared.setDay(key: dayKey, seconds: newSecs)
        isEditing = false
    }
}
