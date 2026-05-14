import SwiftUI

private let presets: [(label: String, minutes: Int)] = [
    ("15 min", 15),
    ("25 min", 25),
    ("30 min", 30),
    ("45 min", 45),
]

struct TimerPanelView: View {
    @StateObject private var timer = PomodoroTimer()
    @State private var customMinutes = ""
    @State private var showCustom = false
    @State private var selectedPreset: Int? = 25

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

            // Presets
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
                            showCustom = false
                            timer.set(minutes: preset.minutes)
                        }
                    }

                    PresetButton(label: "Custom", isSelected: showCustom) {
                        selectedPreset = nil
                        showCustom = true
                    }
                }
                .padding(.horizontal, 12)

                if showCustom {
                    HStack(spacing: 6) {
                        TextField("min", text: $customMinutes)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .frame(width: 50)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.contentBackground))
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 12)

            Spacer()
        }
        .animation(.easeInOut(duration: 0.15), value: showCustom)
    }

    private func applyCustom() {
        guard let mins = Int(customMinutes), mins > 0, mins <= 999 else { return }
        timer.set(minutes: mins)
    }
}
