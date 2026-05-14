import SwiftUI

// MARK: - Unified dispatcher

/// Renders the correct clock face for the active TimerStyle and direction.
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
        case .pulse:
            PulseTimerCircle(
                progress: progress, isFinished: isFinished,
                timeString: timeString, isRunning: isRunning,
                inverted: inverted
            )
        case .radiate:
            RadiateTimerCircle(
                progress: progress, isFinished: isFinished,
                timeString: timeString, isRunning: isRunning,
                inverted: inverted
            )
        case .neon:
            NeonTimerCircle(
                progress: progress, isFinished: isFinished,
                timeString: timeString, inverted: inverted
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
        case .minimal, .radiate:
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
        case .pulse:
            ZStack {
                Circle()
                    .fill(isAccent ? AppTheme.accent : AppTheme.contentBackground)
                Circle()
                    .stroke(AppTheme.accent.opacity(isAccent ? 0.40 : 0.25), lineWidth: 1.5)
                    .padding(-4)
                    .opacity(isAccent ? 1 : 0)
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

    // Inverted: starts full (level=1) and drains to 0
    private var effectiveLevel: CGFloat { inverted ? (1 - progress) : progress }
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

// MARK: - Style 3: Orbit (rocket outside the clock face)

struct OrbitTimerCircle: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    var inverted: Bool = false

    // The clock-face circle the rocket orbits outside of
    private let faceRadius: CGFloat = 36
    // The rocket's orbit is clearly outside the face
    private let orbitRadius: CGFloat = 56

    // Effective angle: both modes start at 12 o'clock (−π/2); direction changes sweep
    private var orbitAngle: CGFloat {
        inverted
            ? -progress * 2 * .pi - .pi / 2   // counter-clockwise from 12
            : progress * 2 * .pi - .pi / 2    // clockwise from 12
    }

    // The rocket should point in the direction of travel (tangent)
    private var rocketFacingDegrees: Double {
        inverted
            ? Double(-progress * 360) - 90    // CCW tangent
            : Double(progress * 360) + 90     // CW tangent
    }

    private var rocketX: CGFloat { cos(orbitAngle) * orbitRadius }
    private var rocketY: CGFloat { sin(orbitAngle) * orbitRadius }

    // Tail progress extents (behind the rocket)
    private var tailStart: CGFloat {
        let rawStart = inverted ? (progress + 0.14) : (progress - 0.14)
        return max(0, min(1, rawStart))
    }

    var body: some View {
        ZStack {
            // Inner clock-face ring (the circle the rocket orbits outside of)
            Circle()
                .stroke(AppTheme.divider.opacity(0.6), lineWidth: 1.5)
                .frame(width: faceRadius * 2, height: faceRadius * 2)

            // Orbit track (faint outer ring)
            Circle()
                .stroke(AppTheme.divider.opacity(0.25), lineWidth: 1)
                .frame(width: orbitRadius * 2, height: orbitRadius * 2)

            // ── Fire trail ──────────────────────────────────────────────
            // Trails drawn via Canvas for noise/turbulence control
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = orbitRadius
                let startA = inverted
                    ? Double(-tailStart * 2 * .pi - .pi / 2)
                    : Double(tailStart * 2 * .pi - .pi / 2)
                let endA = Double(orbitAngle)

                // Make sure we have some visible tail
                guard abs(endA - startA) > 0.01 else { return }

                let cw = !inverted  // clockwise flag for addArc

                // Glow base layer
                var glowPath = Path()
                glowPath.addArc(center: center, radius: R,
                                startAngle: .radians(startA), endAngle: .radians(endA),
                                clockwise: !cw)
                ctx.stroke(glowPath, with: .color(AppTheme.accent.opacity(0.18)),
                           style: StrokeStyle(lineWidth: 14, lineCap: .round))

                // Mid flame layer
                var flamePath = Path()
                flamePath.addArc(center: center, radius: R,
                                 startAngle: .radians(startA), endAngle: .radians(endA),
                                 clockwise: !cw)
                ctx.stroke(flamePath, with: .color(AppTheme.accent.opacity(0.50)),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round))

                // Bright core
                var corePath = Path()
                corePath.addArc(center: center, radius: R,
                                startAngle: .radians(startA), endAngle: .radians(endA),
                                clockwise: !cw)
                ctx.stroke(corePath, with: .color(Color.white.opacity(0.70)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Noisy sparks along the tail (seeded on progress)
                for i in 0..<12 {
                    let fi = CGFloat(i)
                    let t  = fi / 12.0   // 0–1 along tail
                    // Interpolate angle from tip (endA) back toward start (startA)
                    let sparkAngle = endA - (endA - startA) * Double(t)
                    // Pseudo-random radius variance seeded by index + progress
                    let noise  = sin(fi * 7.3 + Double(progress) * 31.4) * 5.0
                    let sparkR = R + noise
                    let sx     = center.x + cos(sparkAngle) * sparkR
                    let sy     = center.y + sin(sparkAngle) * sparkR
                    let sparkSize = (1 - t) * 3.5 + 0.5
                    let alpha  = (1 - t) * 0.85

                    // Color: hot white near tip, orange-ish at tail
                    let sparkColor = t < 0.3
                        ? Color.white.opacity(alpha)
                        : AppTheme.accent.opacity(alpha * 0.7)
                    ctx.fill(Path(ellipseIn: CGRect(
                        x: sx - sparkSize / 2, y: sy - sparkSize / 2,
                        width: sparkSize, height: sparkSize)),
                             with: .color(sparkColor))
                }
            }
            .frame(width: 130, height: 130)
            .animation(.linear(duration: 0.5), value: progress)

            // ── Rocket ────────────────────────────────────────────────
            // Glow halo
            Circle()
                .fill(AppTheme.accent.opacity(0.30))
                .frame(width: 18, height: 18)
                .blur(radius: 5)
                .offset(x: rocketX, y: rocketY)
                .animation(.linear(duration: 0.5), value: progress)

            // Rocket body: a rotated arrow/triangle pointing in direction of travel
            RocketShape()
                .fill(
                    LinearGradient(colors: [Color.white, AppTheme.accentLight],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 10, height: 14)
                .rotationEffect(.degrees(rocketFacingDegrees))
                .offset(x: rocketX, y: rocketY)
                .shadow(color: AppTheme.accent.opacity(0.8), radius: 4)
                .animation(.linear(duration: 0.5), value: progress)

            // ── Time label ────────────────────────────────────────────
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

/// A pointed rocket/arrowhead shape — nose at top, wider at base.
private struct RocketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w / 2, y: 0))              // nose tip
        p.addLine(to: CGPoint(x: w, y: h * 0.6))          // right shoulder
        p.addCurve(to: CGPoint(x: w / 2, y: h),           // base center
                   control1: CGPoint(x: w, y: h * 0.85),
                   control2: CGPoint(x: w * 0.75, y: h))
        p.addCurve(to: CGPoint(x: 0, y: h * 0.6),         // left shoulder
                   control1: CGPoint(x: w * 0.25, y: h),
                   control2: CGPoint(x: 0, y: h * 0.85))
        p.closeSubpath()
        return p
    }
}

// MARK: - Style 4: Pulse (sonar rings)

struct PulseTimerCircle: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    let isRunning: Bool
    var inverted: Bool = false

    // Speed of pulse rings: faster as progress grows (or inverted: slower)
    private var ringSpeed: Double {
        let p = Double(inverted ? (1 - progress) : progress)
        return 0.4 + p * 2.2  // 0.4–2.6 rings/sec
    }

    var body: some View {
        ZStack {
            // Static track ring
            Circle()
                .stroke(AppTheme.divider.opacity(0.4), lineWidth: 1.5)
                .frame(width: 110, height: 110)

            if isRunning {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    pulseRings(t: t)
                }
            } else {
                // Use progress as phase seed so paused appearance varies with session state
                pulseRings(t: Double(inverted ? 1 - progress : progress))
            }

            // Center dot
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 8, height: 8)
                .shadow(color: AppTheme.accent.opacity(0.6), radius: 6)

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

    @ViewBuilder
    private func pulseRings(t: Double) -> some View {
        let maxR: CGFloat = 55
        let minR: CGFloat = 4
        let ringCount = 4

        ForEach(0..<ringCount, id: \.self) { i in
            // Phase offset so rings are staggered evenly
            let phase = (t * ringSpeed + Double(i) / Double(ringCount))
                .truncatingRemainder(dividingBy: 1.0)
            let scale  = CGFloat(phase)          // 0 → 1 (growing)
            let radius = minR + scale * (maxR - minR)
            let opacity = Double(1.0 - phase)    // fades as it expands
            let lineW: CGFloat = 2.0 - scale * 1.0  // thins as it expands

            Circle()
                .stroke(AppTheme.accent.opacity(opacity * 0.75), lineWidth: max(0.5, lineW))
                .frame(width: radius * 2, height: radius * 2)
        }
    }
}

// MARK: - Style 5: Radiate (rotating spoke ring)

struct RadiateTimerCircle: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    let isRunning: Bool
    var inverted: Bool = false

    private let spokeCount = 60
    private let innerR: CGFloat = 44
    private let outerR: CGFloat = 58

    var body: some View {
        ZStack {
            if isRunning {
                TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    spokeCanvas(rotAngle: CGFloat(t * 8.0 * .pi / 180.0))
                }
            } else {
                spokeCanvas(rotAngle: 0)
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

    private func spokeCanvas(rotAngle: CGFloat) -> some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let effectiveP = inverted ? (1 - progress) : progress

            for i in 0..<spokeCount {
                let fi = CGFloat(i)
                let spokeAngle = fi / CGFloat(spokeCount) * 2 * .pi - .pi / 2 + rotAngle
                let spokeFrac  = fi / CGFloat(spokeCount)
                let lit = spokeFrac < effectiveP

                let x1 = center.x + cos(spokeAngle) * innerR
                let y1 = center.y + sin(spokeAngle) * innerR
                let x2 = center.x + cos(spokeAngle) * outerR
                let y2 = center.y + sin(spokeAngle) * outerR

                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x2, y: y2))

                if lit {
                    ctx.stroke(path, with: .color(AppTheme.accent.opacity(0.90)),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    ctx.stroke(path, with: .color(AppTheme.accent.opacity(0.25)),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round))
                } else {
                    ctx.stroke(path, with: .color(AppTheme.divider.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
        }
    }
}

// MARK: - Style 6: Neon (electric plasma arc)

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
