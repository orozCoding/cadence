import SwiftUI

private let presets: [(label: String, minutes: Int)] = [
    ("15 min", 15),
    ("25 min", 25),
    ("30 min", 30),
    ("45 min", 45),
]

struct TimerPanelView: View {
    @ObservedObject private var timer      = PomodoroTimer.shared
    @ObservedObject private var settings   = AppSettings.shared
    @ObservedObject private var focusStore = FocusTimeStore.shared

    @State private var customMinutes = ""
    @State private var selectedPreset: Int? = 25

    var body: some View {
        VStack(spacing: 0) {
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

            // Timer clock — style and direction driven by settings
            TimerClockView(
                style: settings.timerStyle,
                progress: CGFloat(timer.progress),
                isFinished: timer.isFinished,
                timeString: timer.timeString,
                isRunning: timer.isRunning,
                inverted: settings.timerDirection == .inverted
            )

            Spacer().frame(height: 20)

            // Controls
            HStack(spacing: 12) {
                Button(action: timer.reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(TimerButtonBG(style: settings.timerStyle, size: 36, isAccent: false))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                .accessibilityLabel("Reset timer")

                Button(action: timer.toggle) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(TimerButtonBG(style: settings.timerStyle, size: 48, isAccent: true))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .animation(.easeInOut(duration: 0.12), value: timer.isRunning)
                .shadow(color: AppTheme.accent.opacity(0.38), radius: 8, x: 0, y: 4)
                .accessibilityLabel(timer.isRunning ? "Pause timer" : (timer.isFinished ? "Start new session" : "Start timer"))
            }

            // Today's focus time
            let todaySecs = focusStore.todaySeconds()
            Text(todaySecs > 0 ? "Today  \(formatFocusTime(todaySecs))" : "No focus time today")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.top, 10)

            Spacer().frame(height: 20)

            Divider().background(AppTheme.divider)

            // Presets + custom input
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
                        .accessibilityLabel("Custom duration in minutes")
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

            Spacer()
        }
        .onDisappear {
            if timer.isRunning { timer.pause() }
        }
    }

    private func applyCustom() {
        let trimmed = customMinutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Restrict to digits and a decimal separator so Double() can't quietly
        // accept things like "1e2" (scientific notation → 100 min) that the
        // user didn't intend to enter. CharacterSet.decimalDigits covers all
        // Unicode decimal-digit scripts; the separator string includes "." and
        // "," plus the locale's own decimal separator (e.g. "٫" in ar locales).
        var separators = ".,"
        if let sep = Locale.current.decimalSeparator, !separators.contains(sep) {
            separators += sep
        }
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: separators))
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return }
        // Accept dot-decimal ("0.5") regardless of locale, then fall back to
        // locale-aware parsing so comma-decimal users ("0,5") still work.
        // Grouping separator off in the fallback — a 3-digit field shouldn't
        // treat "1,234" as 1234.
        let parsed: Double? = Double(trimmed) ?? {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = .current
            formatter.usesGroupingSeparator = false
            return formatter.number(from: trimmed)?.doubleValue
        }()
        guard let mins = parsed, mins > 0, mins <= 999 else { return }
        selectedPreset = presets.first(where: { Double($0.minutes) == mins })?.minutes
        timer.set(seconds: mins * 60)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

func formatFocusTime(_ seconds: Int) -> String {
    if seconds <= 0 { return "—" }
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return "\(h)h \(m)m \(s)s" }
    if m > 0 { return "\(m)m \(s)s" }
    return "\(s)s"
}
