import SwiftUI

// MARK: - Unified dispatcher

/// Renders the correct clock face for the active TimerStyle and direction.
/// `inverted` is a visual-only flag — all styles derive their fill/position from `progress`,
/// which is always `(1 - remaining/total)` regardless of direction. Flipping `inverted`
/// mid-session is safe and takes effect on the next render with no timer state change.
struct TimerClockView: View {
    let style: TimerStyle
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    let isRunning: Bool
    var inverted: Bool = false
    var isPreview: Bool = false

    var body: some View {
        switch style {
        case .glassy:
            GlassTimerCircle(
                progress: progress, isFinished: isFinished,
                timeString: timeString, isRunning: isRunning,
                inverted: inverted, isPreview: isPreview
            )
        case .minimal:
            MinimalTimerCircle(
                progress: progress, isFinished: isFinished,
                timeString: timeString, inverted: inverted
            )
        case .orbit:
            OrbitTimerCircle(
                progress: progress, isFinished: isFinished,
                timeString: timeString, inverted: inverted
            )
        case .neon:
            NeonTimerCircle(
                progress: progress, isFinished: isFinished,
                timeString: timeString, inverted: inverted
            )
        case .tetris:
            TetrisTimerView(
                progress: progress, isFinished: isFinished,
                timeString: timeString, inverted: inverted
            )
        case .jogger:
            JoggerTimerView(
                progress: progress, isFinished: isFinished,
                timeString: timeString, isRunning: isRunning,
                inverted: inverted, isPreview: isPreview
            )
        case .sand:
            SandTimerView(
                progress: progress, isFinished: isFinished,
                timeString: timeString, isRunning: isRunning,
                inverted: inverted, isPreview: isPreview
            )
        }
    }
}

/// Returns the correct button background circle for the active TimerStyle.
struct TimerButtonBG: View {
    let style: TimerStyle
    let size: CGFloat
    let isAccent: Bool

    var body: some View {
        switch style {
        case .glassy:
            GlassCircle(size: size, isAccent: isAccent)
        case .minimal:
            Circle()
                .fill(isAccent ? AppTheme.accent : AppTheme.divider)
                .frame(width: size, height: size)
        case .orbit:
            ZStack {
                Circle()
                    .fill(isAccent ? AppTheme.accent : Color.clear)
                Circle()
                    .stroke(isAccent ? Color.white.opacity(0.30) : AppTheme.textTertiary,
                            lineWidth: 1.5)
            }
            .frame(width: size, height: size)
        case .neon:
            ZStack {
                Circle()
                    .fill(isAccent ? AppTheme.accent : Color.black.opacity(0.08))
                if isAccent {
                    Circle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 1)
                    Circle()
                        .fill(AppTheme.accent.opacity(0.35))
                        .blur(radius: 6)
                        .padding(-4)
                }
            }
            .frame(width: size, height: size)
        case .tetris:
            // Pixel-tile look: solid square with subtle inset highlight.
            RoundedRectangle(cornerRadius: 4)
                .fill(isAccent ? AppTheme.accent : AppTheme.divider)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(isAccent ? 0.35 : 0.20), lineWidth: 1)
                        .padding(1)
                )
                .frame(width: size, height: size)
        case .jogger:
            // Plain solid circle — keeps controls visually quiet so the runner
            // stays the focus.
            Circle()
                .fill(isAccent ? AppTheme.accent : AppTheme.divider)
                .overlay(
                    Circle().stroke(AppTheme.textTertiary.opacity(isAccent ? 0 : 0.3),
                                    lineWidth: 1)
                )
                .frame(width: size, height: size)
        case .sand:
            // Warm sandy gradient to echo the hourglass palette.
            Circle()
                .fill(
                    isAccent
                    ? LinearGradient(
                        colors: [Color(hex: "#E8B863"), Color(hex: "#B68637")],
                        startPoint: .top, endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [AppTheme.divider, AppTheme.divider],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    Circle().stroke(Color.white.opacity(isAccent ? 0.35 : 0.0), lineWidth: 1)
                )
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Style 1: Glassy liquid fill

// Animatable liquid wave shape
struct LiquidFill: Shape {
    var level: CGFloat
    var phase: CGFloat

    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(level, 0), 1)
        let waveY   = rect.height * (1 - clamped)
        let amplitude: CGFloat = (clamped > 0.02 && clamped < 0.98) ? 5.0 : 0.0

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: waveY))

        let step = max(rect.width / 60, 2)
        var x: CGFloat = 0
        while x <= rect.width {
            let y = waveY + sin((x / rect.width) * .pi * 3 + phase) * amplitude
            path.addLine(to: CGPoint(x: rect.minX + x, y: y))
            x += step
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct GlassTimerCircle: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    let isRunning: Bool
    var inverted: Bool = false
    var isPreview: Bool = false

    @State private var frozenPhase: CGFloat = 0
    @State private var waveStartDate: Date = .now
    @State private var phaseAtStart: CGFloat = 0

    // Original: starts full (level=1) and drains to 0 as time elapses.
    // Inverted: starts empty and fills up as time elapses.
    private var effectiveLevel: CGFloat { inverted ? progress : (1 - progress) }
    // Text is white when liquid is above midpoint
    private var liquidAboveMid: Bool { effectiveLevel > 0.55 }

    var body: some View {
        waveContent
            .frame(width: 130, height: 130)
            .shadow(color: AppTheme.accentDark.opacity(0.22), radius: 12, x: 0, y: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Timer")
            .accessibilityValue(isFinished ? "Done" : timeString)
            .onAppear {
                guard !isPreview else { return }
                let elapsed = PomodoroTimer.shared.total - PomodoroTimer.shared.remaining
                let anchored = CGFloat(elapsed / 4.0) * (.pi * 2)
                frozenPhase  = anchored
                phaseAtStart = anchored
                waveStartDate = .now
            }
            .onChange(of: isRunning) { _, running in
                guard !isPreview else { return }
                if running {
                    waveStartDate = .now
                    phaseAtStart  = frozenPhase
                } else {
                    let elapsed = CGFloat(Date().timeIntervalSince(waveStartDate))
                    frozenPhase = phaseAtStart + elapsed / 4.0 * (.pi * 2)
                }
            }
            .onChange(of: progress) { _, newProgress in
                guard !isPreview, newProgress == 0 else { return }
                frozenPhase  = 0
                phaseAtStart = 0
            }
    }

    @ViewBuilder
    private var waveContent: some View {
        if isRunning {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                let elapsed = CGFloat(context.date.timeIntervalSince(waveStartDate))
                let phase   = phaseAtStart + elapsed / 4.0 * (.pi * 2)
                glassContent(phase: phase)
            }
        } else {
            glassContent(phase: frozenPhase)
        }
    }

    @ViewBuilder
    private func glassContent(phase: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.28), AppTheme.sidebarBackground.opacity(0.40)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            LiquidFill(level: effectiveLevel, phase: phase)
                .fill(LinearGradient(
                    colors: [AppTheme.accentDark, AppTheme.accent.opacity(0.82)],
                    startPoint: .bottom, endPoint: .top
                ))
                .clipShape(Circle())
                .animation(.linear(duration: 0.5), value: effectiveLevel)

            Circle()
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.07), Color.clear, AppTheme.accentDark.opacity(0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                .padding(5)

            Ellipse()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.58), Color.clear],
                    center: .center, startRadius: 0, endRadius: 26
                ))
                .frame(width: 52, height: 22)
                .offset(x: -17, y: -34)
                .rotationEffect(.degrees(-25))
                .blendMode(.plusLighter)

            VStack(spacing: 2) {
                Text(timeString)
                    .font(.system(size: 28, weight: .thin, design: .monospaced))
                    .foregroundStyle(liquidAboveMid ? Color.white : AppTheme.textPrimary)
                    .contentTransition(.numericText())
                    .shadow(
                        color: liquidAboveMid
                            ? AppTheme.accentDark.opacity(0.55)
                            : Color.black.opacity(0.08),
                        radius: 3
                    )
                    .animation(.easeInOut(duration: 0.35), value: effectiveLevel)
                if isFinished {
                    Text("Done!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(liquidAboveMid ? Color.white : AppTheme.accent)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .clipShape(Circle())
        .overlay(
            Circle().stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.88), AppTheme.accentLight.opacity(0.45),
                        AppTheme.accentDark.opacity(0.35), Color.white.opacity(0.55)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 5
            )
        )
    }
}

struct GlassCircle: View {
    let size: CGFloat
    let isAccent: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    isAccent
                    ? LinearGradient(
                        colors: [AppTheme.accentLight, AppTheme.accentDark],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [Color.white.opacity(0.65), AppTheme.divider.opacity(0.90)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.45), Color.clear],
                    startPoint: .top, endPoint: .center
                ))
            Circle()
                .stroke(
                    LinearGradient(
                        colors: isAccent
                            ? [Color.white.opacity(0.72), AppTheme.accent.opacity(0.22)]
                            : [Color.white.opacity(0.90), AppTheme.divider.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Style 2: Minimal

struct MinimalTimerCircle: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    var inverted: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.divider, lineWidth: 6)

            // Original: clockwise from 12 o'clock
            // Inverted: counter-clockwise from 12 o'clock (horizontal mirror of arc)
            Group {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isFinished ? AppTheme.accentDark : AppTheme.accent,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)
            }
            .scaleEffect(x: inverted ? -1 : 1, y: 1)

            VStack(spacing: 2) {
                Text(timeString)
                    .font(.system(size: 28, weight: .thin, design: .monospaced))
                    .foregroundStyle(isFinished ? AppTheme.accent : AppTheme.textPrimary)
                    .contentTransition(.numericText())
                if isFinished {
                    Text("Done!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .frame(width: 130, height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue(isFinished ? "Done" : timeString)
    }
}

// MARK: - Style 3: Orbit (comet orbiting outside the clock face)

struct OrbitTimerCircle: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    var inverted: Bool = false

    // Inner face ring the comet orbits outside of
    private let faceRadius: CGFloat = 40
    // Comet orbits at a larger radius, clearly outside the face
    private let orbitRadius: CGFloat = 56

    private var angle: CGFloat {
        inverted
            ? -progress * 2 * .pi - .pi / 2   // CCW from 12
            : progress * 2 * .pi - .pi / 2    // CW from 12
    }
    private var dotX: CGFloat { cos(angle) * orbitRadius }
    private var dotY: CGFloat { sin(angle) * orbitRadius }

    var body: some View {
        ZStack {
            // Inner clock-face ring
            Circle()
                .stroke(AppTheme.divider, lineWidth: 2)
                .frame(width: faceRadius * 2, height: faceRadius * 2)

            // Faint orbit track
            Circle()
                .stroke(AppTheme.divider.opacity(0.35), lineWidth: 1)
                .frame(width: orbitRadius * 2, height: orbitRadius * 2)

            // Full elapsed arc on the orbit track (faint)
            Group {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(AppTheme.accent.opacity(0.22), lineWidth: 3)
                    .frame(width: orbitRadius * 2, height: orbitRadius * 2)

                // Short comet tail
                Circle()
                    .trim(from: max(0, progress - 0.09), to: progress)
                    .stroke(AppTheme.accent.opacity(0.75),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: orbitRadius * 2, height: orbitRadius * 2)
            }
            .rotationEffect(.degrees(-90))
            .scaleEffect(x: inverted ? -1 : 1, y: 1)
            .animation(.linear(duration: 0.5), value: progress)

            // Glow halo
            Circle()
                .fill(AppTheme.accent.opacity(0.28))
                .frame(width: 16, height: 16)
                .blur(radius: 4)
                .offset(x: dotX, y: dotY)
                .animation(.linear(duration: 0.5), value: progress)

            // Comet dot
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 9, height: 9)
                .overlay(Circle().fill(Color.white.opacity(0.5)).padding(3))
                .shadow(color: AppTheme.accent.opacity(0.6), radius: 4)
                .offset(x: dotX, y: dotY)
                .animation(.linear(duration: 0.5), value: progress)

            VStack(spacing: 2) {
                Text(timeString)
                    .font(.system(size: 28, weight: .thin, design: .monospaced))
                    .foregroundStyle(isFinished ? AppTheme.accent : AppTheme.textPrimary)
                    .contentTransition(.numericText())
                if isFinished {
                    Text("Done!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .frame(width: 130, height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue(isFinished ? "Done" : timeString)
    }
}

// MARK: - Style 4: Neon (electric plasma arc)

struct NeonTimerCircle: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    var inverted: Bool = false

    private let radius: CGFloat = 55

    // Arc angle for the tip spark
    private var tipAngle: CGFloat {
        inverted
            ? -progress * 2 * .pi - .pi / 2
            : progress * 2 * .pi - .pi / 2
    }
    private var tipX: CGFloat { cos(tipAngle) * radius }
    private var tipY: CGFloat { sin(tipAngle) * radius }

    var body: some View {
        ZStack {
            // Ambient under-glow track
            Circle()
                .stroke(AppTheme.accent.opacity(0.05), lineWidth: 18)

            // Arc layers (mirrored horizontally for inverted direction)
            Group {
                // Outer diffuse glow
                Circle()
                    .trim(from: 0, to: max(progress, 0.002))
                    .stroke(AppTheme.accent.opacity(0.20), lineWidth: 18)
                    .blur(radius: 7)

                // Mid glow
                Circle()
                    .trim(from: 0, to: max(progress, 0.002))
                    .stroke(AppTheme.accent.opacity(0.45), lineWidth: 8)
                    .blur(radius: 3)

                // Bright inner arc
                Circle()
                    .trim(from: 0, to: max(progress, 0.002))
                    .stroke(AppTheme.accentLight.opacity(0.85), lineWidth: 3)

                // Crisp white core
                Circle()
                    .trim(from: 0, to: max(progress, 0.002))
                    .stroke(Color.white.opacity(0.70), lineWidth: 1.2)
            }
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 0.5), value: progress)
            .scaleEffect(x: inverted ? -1 : 1, y: 1)

            // Tip spark — always visible, sits at 12 o'clock when progress=0
            ZStack {
                // Halo
                Circle()
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 20, height: 20)
                    .blur(radius: 6)
                // Core spark
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .shadow(color: AppTheme.accent, radius: 5)
            }
            .offset(x: tipX, y: tipY)
            .animation(.linear(duration: 0.5), value: progress)

            // Time label
            VStack(spacing: 2) {
                Text(timeString)
                    .font(.system(size: 28, weight: .thin, design: .monospaced))
                    .foregroundStyle(isFinished ? AppTheme.accent : AppTheme.textPrimary)
                    .contentTransition(.numericText())
                if isFinished {
                    Text("Done!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .frame(width: 130, height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue(isFinished ? "Done" : timeString)
    }
}
