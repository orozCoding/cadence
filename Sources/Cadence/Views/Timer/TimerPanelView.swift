import SwiftUI

private let presets: [(label: String, minutes: Int)] = [
    ("15 min", 15),
    ("25 min", 25),
    ("30 min", 30),
    ("45 min", 45),
]

// MARK: - Liquid wave shape

private struct LiquidFill: Shape {
    var level: CGFloat   // 0 = empty, 1 = full
    var phase: CGFloat   // wave phase — not in animatableData, updated per frame

    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(level, 0), 1)
        let waveY   = rect.height * (1 - clamped)
        // Suppress the wave at near-empty / near-full so edges look clean
        let amplitude: CGFloat = (clamped > 0.02 && clamped < 0.98) ? 5.0 : 0.5

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: waveY))

        var x: CGFloat = 0
        while x <= rect.width {
            let y = waveY + sin((x / rect.width) * .pi * 3 + phase) * amplitude
            path.addLine(to: CGPoint(x: rect.minX + x, y: y))
            x += 2
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Glass timer circle

private struct GlassTimerCircle: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / 30)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let phase   = CGFloat(elapsed.truncatingRemainder(dividingBy: 4.0)) / 4.0 * (.pi * 2)
            glassContent(phase: phase)
        }
        .frame(width: 130, height: 130)
        // Soft drop shadow for the whole glass
        .shadow(color: AppTheme.accentDark.opacity(0.22), radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private func glassContent(phase: CGFloat) -> some View {
        ZStack {
            // ── Frosted glass body ─────────────────────────────────────────
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            AppTheme.sidebarBackground.opacity(0.40)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // ── Blue liquid fill (animates with progress) ─────────────────
            LiquidFill(level: progress, phase: phase)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accentDark, AppTheme.accent.opacity(0.82)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .clipShape(Circle())
                .animation(.linear(duration: 0.5), value: progress)

            // ── Inner depth gradient (glass volume illusion) ───────────────
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.07),
                            Color.clear,
                            AppTheme.accentDark.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // ── Glass rim ─────────────────────────────────────────────────
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.88),
                            AppTheme.accentLight.opacity(0.45),
                            AppTheme.accentDark.opacity(0.35),
                            Color.white.opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 5
                )

            // ── Inner rim fine highlight ───────────────────────────────────
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                .padding(5)

            // ── Specular / glossy highlight (top-left) ────────────────────
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.58), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 26
                    )
                )
                .frame(width: 52, height: 22)
                .offset(x: -17, y: -34)
                .rotationEffect(.degrees(-25))
                .blendMode(.plusLighter)

            // ── Timer label ───────────────────────────────────────────────
            VStack(spacing: 2) {
                Text(timeString)
                    .font(.system(size: 28, weight: .thin, design: .monospaced))
                    .foregroundStyle(progress > 0.55 ? Color.white : AppTheme.textPrimary)
                    .contentTransition(.numericText())
                    .shadow(
                        color: progress > 0.55
                            ? AppTheme.accentDark.opacity(0.55)
                            : Color.black.opacity(0.08),
                        radius: 3
                    )
                    .animation(.easeInOut(duration: 0.35), value: progress > 0.55)

                if isFinished {
                    Text("Done!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        // Clip everything (including the specular highlight) to the circle
        .clipShape(Circle())
        // Re-draw the rim on top of the clip so it isn't cut
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.88),
                            AppTheme.accentLight.opacity(0.45),
                            AppTheme.accentDark.opacity(0.35),
                            Color.white.opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 5
                )
        )
    }
}

// MARK: - Glassy circle button background

private struct GlassCircle: View {
    let size: CGFloat
    let isAccent: Bool

    var body: some View {
        ZStack {
            // Base fill with glass gradient
            Circle()
                .fill(
                    isAccent
                    ? LinearGradient(
                        colors: [AppTheme.accentLight, AppTheme.accentDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [Color.white.opacity(0.65), AppTheme.divider.opacity(0.90)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Upper-half shine
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            // Rim
            Circle()
                .stroke(
                    LinearGradient(
                        colors: isAccent
                            ? [Color.white.opacity(0.72), AppTheme.accent.opacity(0.22)]
                            : [Color.white.opacity(0.90), AppTheme.divider.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - TimerPanelView

struct TimerPanelView: View {
    @ObservedObject private var timer = PomodoroTimer.shared
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

            // Glass clock
            GlassTimerCircle(
                progress: timer.progress,
                isFinished: timer.isFinished,
                timeString: timer.timeString
            )

            Spacer().frame(height: 20)

            // Controls
            HStack(spacing: 12) {
                Button(action: timer.reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(GlassCircle(size: 36, isAccent: false))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)

                Button(action: timer.toggle) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(GlassCircle(size: 48, isAccent: true))
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .animation(.easeInOut(duration: 0.12), value: timer.isRunning)
                .shadow(color: AppTheme.accent.opacity(0.38), radius: 8, x: 0, y: 4)
            }

            // Today's focus time — inline below controls
            let todaySecs = focusStore.todaySeconds()
            Text(todaySecs > 0 ? "Today  \(formatFocusTime(todaySecs))" : "No focus time today")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.top, 10)

            Spacer().frame(height: 20)

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

            Spacer()
        }
    }

    private func applyCustom() {
        guard let mins = Double(customMinutes), mins > 0, mins <= 999 else { return }
        selectedPreset = nil
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
