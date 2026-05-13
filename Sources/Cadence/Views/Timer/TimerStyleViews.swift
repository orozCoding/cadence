import SwiftUI

// MARK: - Unified dispatcher

/// Renders the correct clock face and button backgrounds for the active TimerStyle.
struct TimerClockView: View {
    let style: TimerStyle
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    let isRunning: Bool
    var isPreview: Bool = false

    var body: some View {
        switch style {
        case .glassy:
            GlassTimerCircle(
                progress: progress, isFinished: isFinished,
                timeString: timeString, isRunning: isRunning,
                isPreview: isPreview
            )
        case .minimal:
            MinimalTimerCircle(
                progress: progress, isFinished: isFinished, timeString: timeString
            )
        case .orbit:
            OrbitTimerCircle(
                progress: progress, isFinished: isFinished, timeString: timeString
            )
        case .segments:
            SegmentsTimerCircle(
                progress: progress, isFinished: isFinished, timeString: timeString
            )
        case .dots:
            DotRingTimerCircle(
                progress: progress, isFinished: isFinished, timeString: timeString
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
        case .minimal, .segments:
            Circle()
                .fill(isAccent ? AppTheme.accent : AppTheme.divider)
                .frame(width: size, height: size)
        case .orbit:
            ZStack {
                // Accent button: solid fill keeps white icon readable (WCAG AA).
                // Reset button: transparent with ring, matching the orbit aesthetic.
                Circle()
                    .fill(isAccent ? AppTheme.accent : Color.clear)
                Circle()
                    .stroke(isAccent ? Color.white.opacity(0.30) : AppTheme.textTertiary,
                            lineWidth: 1.5)
            }
            .frame(width: size, height: size)
        case .dots:
            ZStack {
                Circle()
                    .fill(isAccent ? AppTheme.accent : AppTheme.divider)
                if isAccent {
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 2)
                        .padding(6)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Style 1: Glassy liquid fill

// Stores wave phase so it survives style-switch round-trips.
@MainActor
private final class GlassWaveState {
    static let shared = GlassWaveState()
    var phase: CGFloat = 0
    var disappearDate: Date? = nil
    var disappearIsRunning: Bool = false
}

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
    var isPreview: Bool = false

    @State private var frozenPhase: CGFloat = 0
    @State private var waveStartDate: Date = .now
    @State private var phaseAtStart: CGFloat = 0

    var body: some View {
        waveContent
            .frame(width: 130, height: 130)
            .shadow(color: AppTheme.accentDark.opacity(0.22), radius: 12, x: 0, y: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Timer")
            .accessibilityValue(isFinished ? "Done" : timeString)
            .onAppear {
                guard !isPreview else { return }
                let saved = GlassWaveState.shared.phase
                // If the timer was running while Glassy was hidden, advance the phase
                // by the time elapsed during the hidden period so the wave is continuous.
                // Advance wave phase by time elapsed while hidden, but only if the timer
                // was running when Glassy was hidden (paused-when-left → no advance).
                let hiddenAdvance: CGFloat
                if GlassWaveState.shared.disappearIsRunning,
                   let d = GlassWaveState.shared.disappearDate {
                    hiddenAdvance = CGFloat(Date().timeIntervalSince(d)) / 4.0 * (.pi * 2)
                } else {
                    hiddenAdvance = 0
                }
                GlassWaveState.shared.disappearDate = nil
                GlassWaveState.shared.disappearIsRunning = false
                frozenPhase  = saved
                phaseAtStart = saved + hiddenAdvance
                waveStartDate = .now
            }
            .onDisappear {
                guard !isPreview else { return }
                GlassWaveState.shared.disappearDate = Date()
                GlassWaveState.shared.disappearIsRunning = isRunning
                if isRunning {
                    let elapsed = CGFloat(Date().timeIntervalSince(waveStartDate))
                    GlassWaveState.shared.phase = phaseAtStart + elapsed / 4.0 * (.pi * 2)
                } else {
                    GlassWaveState.shared.phase = frozenPhase
                }
            }
            .onChange(of: isRunning) { _, running in
                guard !isPreview else { return }
                if running {
                    waveStartDate = .now
                    phaseAtStart  = frozenPhase
                } else {
                    let elapsed = CGFloat(Date().timeIntervalSince(waveStartDate))
                    frozenPhase = phaseAtStart + elapsed / 4.0 * (.pi * 2)
                    GlassWaveState.shared.phase = frozenPhase
                }
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

            LiquidFill(level: progress, phase: phase)
                .fill(LinearGradient(
                    colors: [AppTheme.accentDark, AppTheme.accent.opacity(0.82)],
                    startPoint: .bottom, endPoint: .top
                ))
                .clipShape(Circle())
                .animation(.linear(duration: 0.5), value: progress)

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
                    .foregroundStyle(progress > 0.55 ? Color.white : AppTheme.textPrimary)
                    .contentTransition(.numericText())
                    .shadow(
                        color: progress > 0.55
                            ? AppTheme.accentDark.opacity(0.55)
                            : Color.black.opacity(0.08),
                        radius: 3
                    )
                    .animation(.easeInOut(duration: 0.35), value: progress)
                if isFinished {
                    Text("Done!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white)
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

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.divider, lineWidth: 6)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isFinished ? AppTheme.accentDark : AppTheme.accent,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
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

// MARK: - Style 3: Orbit

struct OrbitTimerCircle: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String

    private let orbitRadius: CGFloat = 55

    private var angle: CGFloat { progress * 2 * .pi - .pi / 2 }
    private var dotX: CGFloat   { cos(angle) * orbitRadius }
    private var dotY: CGFloat   { sin(angle) * orbitRadius }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(AppTheme.divider, lineWidth: 2)

            // Full elapsed arc (faint) — zero-length trim is invisible at progress=0
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AppTheme.accent.opacity(0.22), lineWidth: 3)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)

            // Short comet tail
            Circle()
                .trim(from: max(0, progress - 0.09), to: progress)
                .stroke(AppTheme.accent.opacity(0.75),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)

            // Glow halo — always visible, sits at 12 o'clock when progress=0
            Circle()
                .fill(AppTheme.accent.opacity(0.28))
                .frame(width: 16, height: 16)
                .blur(radius: 4)
                .offset(x: dotX, y: dotY)
                .animation(.linear(duration: 0.5), value: progress)

            // Dot
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 9, height: 9)
                .overlay(Circle().fill(Color.white.opacity(0.5)).padding(3))
                .shadow(color: AppTheme.accent.opacity(0.6), radius: 4)
                .offset(x: dotX, y: dotY)
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

// MARK: - Style 4: Segments

struct SegmentsTimerCircle: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String

    private let segmentCount = 48

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 10
                let lineWidth: CGFloat = 7
                let segAngle = 2.0 * Double.pi / Double(segmentCount)
                let gap      = segAngle * 0.22

                for i in 0..<segmentCount {
                    let startA = segAngle * Double(i) - Double.pi / 2 + gap / 2
                    let endA   = segAngle * Double(i + 1) - Double.pi / 2 - gap / 2

                    var path = Path()
                    path.addArc(center: center, radius: radius,
                                startAngle: .radians(startA),
                                endAngle: .radians(endA), clockwise: false)

                    let segP = CGFloat(i) / CGFloat(segmentCount)
                    let filled = segP < progress
                    let color: Color = filled
                        ? (isFinished ? AppTheme.accentDark : AppTheme.accent)
                        : AppTheme.divider

                    context.stroke(path, with: .color(color),
                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }

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

// MARK: - Style 5: Dot Ring

struct DotRingTimerCircle: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String

    private let dotCount  = 48
    private let ringRadius: CGFloat = 52

    var body: some View {
        ZStack {
            ForEach(0..<dotCount, id: \.self) { i in
                let angle      = CGFloat(i) / CGFloat(dotCount) * 2 * .pi - .pi / 2
                let dotP       = CGFloat(i) / CGFloat(dotCount)
                let filled     = dotP < progress
                let dotSize: CGFloat = filled ? 7 : 4
                let dotColor: Color  = filled
                    ? (isFinished ? AppTheme.accentDark : AppTheme.accent)
                    : AppTheme.divider

                Circle()
                    .fill(dotColor)
                    .frame(width: dotSize, height: dotSize)
                    .shadow(color: filled ? AppTheme.accent.opacity(0.5) : .clear, radius: 3)
                    .offset(x: cos(angle) * ringRadius, y: sin(angle) * ringRadius)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: filled)
            }

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
        .drawingGroup()
        .frame(width: 130, height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue(isFinished ? "Done" : timeString)
    }
}
