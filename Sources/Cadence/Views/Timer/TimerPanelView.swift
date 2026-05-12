import SwiftUI

private let presets: [(label: String, minutes: Int)] = [
    ("15 min", 15),
    ("25 min", 25),
    ("30 min", 30),
    ("45 min", 45),
]

struct TimerPanelView: View {
    @StateObject private var timer = PomodoroTimer()
    @ObservedObject private var focusStore = FocusTimeStore.shared
    @EnvironmentObject var settings: AppSettings

    @State private var customMinutes = ""
    @State private var selectedPreset: Int? = 25
    @State private var showFocusStats = true

    var body: some View {
        VStack(spacing: 0) {
            // Panel title
            HStack {
                Text("Focus Timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().background(AppTheme.divider)

            Spacer()

            // Clock ring
            ZStack {
                Circle()
                    .stroke(AppTheme.divider, lineWidth: 6)
                    .frame(width: 130, height: 130)

                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(
                        timer.isFinished ? AppTheme.accentDark : AppTheme.accent,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)

                VStack(spacing: 2) {
                    Text(timer.timeString)
                        .font(.system(size: 28, weight: .thin, design: .monospaced))
                        .foregroundStyle(timer.isFinished ? AppTheme.accent : AppTheme.textPrimary)
                        .contentTransition(.numericText())

                    if timer.isFinished {
                        Text("Done!")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
            }

            Spacer().frame(height: 20)

            // Controls
            HStack(spacing: 12) {
                Button(action: timer.reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AppTheme.divider))
                }
                .buttonStyle(.plain)
                .pointerCursor()

                Button(action: timer.toggle) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(AppTheme.accent))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .animation(.easeInOut(duration: 0.12), value: timer.isRunning)
            }

            Spacer().frame(height: 24)

            Divider().background(AppTheme.divider)

            // Presets + always-visible custom input
            VStack(alignment: .leading, spacing: 8) {
                Text("Presets")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .padding(.horizontal, 16)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(presets, id: \.minutes) { preset in
                        PresetButton(
                            label: preset.label,
                            isSelected: selectedPreset == preset.minutes
                        ) {
                            selectedPreset = preset.minutes
                            timer.set(minutes: preset.minutes)
                        }
                    }
                }
                .padding(.horizontal, 12)

                // Custom input — always visible
                HStack(spacing: 8) {
                    Text("Custom")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    TextField("min", text: $customMinutes)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 44)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(AppTheme.contentBackground))
                        .onSubmit { applyCustom() }
                    Text("min")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                    Button("Set") { applyCustom() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .pointerCursor()
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)

            Divider().background(AppTheme.divider)

            // Focus time stats — collapsible
            VStack(alignment: .leading, spacing: 0) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showFocusStats.toggle() } }) {
                    HStack(spacing: 5) {
                        Text("Focus Time")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                        Image(systemName: showFocusStats ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, showFocusStats ? 8 : 12)

                if showFocusStats {
                    VStack(spacing: 4) {
                        FocusStatRow(label: "Today", seconds: focusStore.todaySeconds()) { newSecs in
                            focusStore.setToday(seconds: newSecs)
                        }
                        FocusStatRow(label: "This week", seconds: focusStore.weekSeconds(weekStartsOn: settings.weekStartsOn)) { newSecs in
                            focusStore.setWeek(to: newSecs, weekStartsOn: settings.weekStartsOn)
                        }
                        FocusStatRow(label: "This month", seconds: focusStore.monthSeconds()) { newSecs in
                            focusStore.setMonth(to: newSecs)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }

            Spacer()
        }
    }

    private func applyCustom() {
        guard let mins = Int(customMinutes), mins > 0, mins <= 999 else { return }
        selectedPreset = nil
        timer.set(minutes: mins)
    }
}

struct PresetButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : AppTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? AppTheme.accent : AppTheme.divider)
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}

struct FocusStatRow: View {
    let label: String
    let seconds: Int
    let onSet: (Int) -> Void

    @State private var isEditing = false
    @State private var editBuffer = ""
    @State private var editError = false

    private var formatted: String {
        if seconds <= 0 { return "—" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            if isEditing {
                HStack(spacing: 4) {
                    TextField("", text: $editBuffer)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(editError ? AppTheme.destructive : AppTheme.textPrimary)
                        .frame(width: 56)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { commitEdit() }
                        .onChange(of: editBuffer) { editError = false }
                    Text("s")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                    Button(action: commitEdit) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    Button(action: { isEditing = false; editError = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            } else {
                Button(action: startEditing) {
                    Text(formatted)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(seconds > 0 ? AppTheme.textPrimary : AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityLabel("\(label): \(formatted). Click to edit.")
            }
        }
    }

    private func startEditing() {
        editBuffer = "\(seconds)"
        editError = false
        isEditing = true
    }

    private func commitEdit() {
        guard let newSecs = Int(editBuffer), newSecs >= 0 else {
            editError = true
            return
        }
        onSet(newSecs)
        isEditing = false
    }
}
