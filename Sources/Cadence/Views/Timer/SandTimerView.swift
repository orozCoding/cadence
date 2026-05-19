import SwiftUI

/// Hourglass-style timer: grains drain from the top chamber, stream through the
/// neck, and pile up in the bottom chamber as time elapses.
///
/// `inverted` swaps the direction of flow without rotating the view (so the
/// time label stays upright): the top chamber fills while the bottom drains,
/// and the grain stream flows upward.
struct SandTimerView: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    let isRunning: Bool
    var inverted: Bool = false
    var isPreview: Bool = false

    private static let size: CGFloat = 130
    private static let frameWidth: CGFloat = 92
    private static let frameHeight: CGFloat = 116
    private static let capHeight: CGFloat = 6
    private static let neckHalfWidth: CGFloat = 4

    private static let sandColor = Color(hex: "#E8B863")
    private static let sandShadow = Color(hex: "#B68637")

    /// Fraction of sand remaining in the top chamber. 1 = full, 0 = empty.
    private var topFill: CGFloat {
        inverted ? progress : (1 - progress)
    }

    /// Fraction of sand accumulated in the bottom chamber. 0 = empty, 1 = full.
    private var bottomFill: CGFloat {
        inverted ? (1 - progress) : progress
    }

    var body: some View {
        ZStack {
            // Glass body
            HourglassOutline(neckHalfWidth: Self.neckHalfWidth)
                .stroke(AppTheme.textPrimary.opacity(0.55), lineWidth: 1.5)
                .frame(width: Self.frameWidth, height: Self.frameHeight)
                .background(
                    HourglassOutline(neckHalfWidth: Self.neckHalfWidth)
                        .fill(Color.white.opacity(0.45))
                        .frame(width: Self.frameWidth, height: Self.frameHeight)
                )

            // Sand in both chambers, clipped to the glass shape
            sandLayer
                .frame(width: Self.frameWidth, height: Self.frameHeight)

            // Falling stream + grains
            grainsLayer
                .frame(width: Self.frameWidth, height: Self.frameHeight)

            // Top & bottom caps
            VStack {
                Capsule()
                    .fill(AppTheme.textPrimary.opacity(0.8))
                    .frame(width: Self.frameWidth + 8, height: Self.capHeight)
                Spacer()
                Capsule()
                    .fill(AppTheme.textPrimary.opacity(0.8))
                    .frame(width: Self.frameWidth + 8, height: Self.capHeight)
            }
            .frame(width: Self.frameWidth + 8, height: Self.frameHeight + 4)

            // Time label — anchored at the neck so it stays readable regardless
            // of which chamber is filling.
            VStack(spacing: 2) {
                Text(timeString)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.white.opacity(0.85))
                    )
                if isFinished {
                    Text("Done!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue(isFinished ? "Done" : timeString)
    }

    // MARK: - Sand fill

    @ViewBuilder
    private var sandLayer: some View {
        ZStack {
            TopSandShape(fillFraction: topFill, neckHalfWidth: Self.neckHalfWidth)
                .fill(
                    LinearGradient(
                        colors: [Self.sandColor, Self.sandShadow],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            BottomSandShape(fillFraction: bottomFill, neckHalfWidth: Self.neckHalfWidth)
                .fill(
                    LinearGradient(
                        colors: [Self.sandColor.opacity(0.95), Self.sandShadow],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
        .clipShape(HourglassOutline(neckHalfWidth: Self.neckHalfWidth))
        .animation(.linear(duration: 0.5), value: progress)
    }

    // MARK: - Falling grains

    @ViewBuilder
    private var grainsLayer: some View {
        if isRunning && !isPreview && progress > 0 && progress < 1 && !isFinished {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                Canvas { ctx, size in
                    drawStream(ctx: ctx, size: size,
                               time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        } else {
            Color.clear
        }
    }

    private func drawStream(ctx: GraphicsContext, size: CGSize, time: TimeInterval) {
        let centerX = size.width / 2
        let neckY = size.height / 2

        // Stream travels between the neck and the receiving pile's surface.
        // Original: neck → bottom pile. Inverted: neck → top pile.
        let pileSurfaceY: CGFloat
        if inverted {
            // Top pile: surface drops from minY (full) to neck (empty) as top fills.
            pileSurfaceY = max(12, neckY - (neckY - 12) * topFill)
        } else {
            pileSurfaceY = min(size.height - 12, neckY + (neckY - 12) * bottomFill)
        }

        // Stream line
        let yStart = min(neckY, pileSurfaceY)
        let yEnd = max(neckY, pileSurfaceY)
        guard yEnd - yStart > 1 else { return }
        let streamRect = CGRect(x: centerX - 0.6, y: yStart,
                                width: 1.2, height: yEnd - yStart)
        ctx.fill(Path(streamRect), with: .color(Self.sandColor.opacity(0.85)))

        // Individual grains travel along the stream.
        let grainCount = 6
        for i in 0..<grainCount {
            let phase = Double(i) / Double(grainCount)
            let cycle = (time * 1.4 + phase).truncatingRemainder(dividingBy: 1.0)
            // Inverted: cycle 0 → at pileSurface (top), 1 → at neck. Otherwise cycle goes neck → pile.
            let along = inverted ? CGFloat(1 - cycle) : CGFloat(cycle)
            let y = neckY + along * (pileSurfaceY - neckY)
            let wobble = sin(time * 6 + Double(i)) * 0.8
            let grain = CGRect(x: centerX - 1 + wobble, y: y - 1, width: 2, height: 2)
            ctx.fill(Path(ellipseIn: grain), with: .color(Self.sandShadow))
        }
    }
}

/// Hourglass outline: two trapezoids meeting at a narrow neck.
private struct HourglassOutline: Shape {
    let neckHalfWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let neckHeight: CGFloat = 6
        let centerX = rect.midX
        let centerY = rect.midY

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: centerX + neckHalfWidth, y: centerY - neckHeight / 2))
        p.addLine(to: CGPoint(x: centerX + neckHalfWidth, y: centerY + neckHeight / 2))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: centerX - neckHalfWidth, y: centerY + neckHeight / 2))
        p.addLine(to: CGPoint(x: centerX - neckHalfWidth, y: centerY - neckHeight / 2))
        p.closeSubpath()
        return p
    }
}

/// Sand in the top chamber. `fillFraction` 1 = full, 0 = empty.
///
/// The filled region is the trapezoid between the sand surface (which rises
/// from the neck at f=0 to the top edge at f=1) and the neck.
private struct TopSandShape: Shape {
    var fillFraction: CGFloat
    let neckHalfWidth: CGFloat

    var animatableData: CGFloat {
        get { fillFraction }
        set { fillFraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let f = max(0, min(1, fillFraction))
        let centerY = rect.midY
        let chamberHeight = centerY - rect.minY
        // Surface rises from centerY (empty) to rect.minY (full).
        let surfaceY = centerY - chamberHeight * f
        // Wall x positions are linearly interpolated between neck (centerY)
        // and the top edge (rect.minY).
        // tSurface: 0 at neck, 1 at top edge.
        let tSurface = (centerY - surfaceY) / max(chamberHeight, 1)
        let leftX = lerp(rect.midX - neckHalfWidth, rect.minX, t: tSurface)
        let rightX = lerp(rect.midX + neckHalfWidth, rect.maxX, t: tSurface)

        var p = Path()
        // Surface line (top of sand) — slight dip in the middle for a settled look.
        p.move(to: CGPoint(x: leftX, y: surfaceY))
        p.addLine(to: CGPoint(x: rect.midX, y: surfaceY + 1.5))
        p.addLine(to: CGPoint(x: rightX, y: surfaceY))
        // Down the right wall to the neck.
        p.addLine(to: CGPoint(x: rect.midX + neckHalfWidth, y: centerY))
        // Across the neck.
        p.addLine(to: CGPoint(x: rect.midX - neckHalfWidth, y: centerY))
        // Back up the left wall to the surface.
        p.closeSubpath()
        return p
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        return a + (b - a) * clamped
    }
}

/// Sand in the bottom chamber. `fillFraction` 0 = empty, 1 = full.
///
/// The filled region is the trapezoid between the pile surface (which rises
/// from the floor at f=0 to the neck at f=1) and the floor.
private struct BottomSandShape: Shape {
    var fillFraction: CGFloat
    let neckHalfWidth: CGFloat

    var animatableData: CGFloat {
        get { fillFraction }
        set { fillFraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let f = max(0, min(1, fillFraction))
        let centerY = rect.midY
        let chamberHeight = rect.maxY - centerY
        // Surface rises from rect.maxY (empty) to centerY (full).
        let surfaceY = rect.maxY - chamberHeight * f
        // tSurface: 0 at floor, 1 at neck.
        let tSurface = (rect.maxY - surfaceY) / max(chamberHeight, 1)
        let leftX = lerp(rect.minX, rect.midX - neckHalfWidth, t: tSurface)
        let rightX = lerp(rect.maxX, rect.midX + neckHalfWidth, t: tSurface)

        var p = Path()
        // Surface line (top of pile) — small mound in the middle.
        p.move(to: CGPoint(x: leftX, y: surfaceY))
        p.addLine(to: CGPoint(x: rect.midX, y: surfaceY - 3))
        p.addLine(to: CGPoint(x: rightX, y: surfaceY))
        // Down the right wall to the floor.
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Across the floor.
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Back up the left wall.
        p.closeSubpath()
        return p
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        return a + (b - a) * clamped
    }
}
