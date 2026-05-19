import SwiftUI

/// Hourglass-style timer: grains drain from the top chamber, stream through the
/// neck, and pile up in the bottom chamber as time elapses.
struct SandTimerView: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    let isRunning: Bool
    var inverted: Bool = false
    var isPreview: Bool = false

    private static let size: CGFloat = 130
    private static let bulbWidth: CGFloat = 78
    private static let bulbHeight: CGFloat = 50    // half-height of each bulb
    private static let neckRadius: CGFloat = 4
    private static let frameWidth: CGFloat = 92    // exterior bounding box (caps + sides)
    private static let frameHeight: CGFloat = 116
    private static let capHeight: CGFloat = 6

    // Sand color
    private static let sandColor = Color(hex: "#E8B863")
    private static let sandShadow = Color(hex: "#B68637")

    private var effectiveProgress: CGFloat {
        // Inverted flips the orientation so sand piles in the top instead.
        // Easiest way: just rotate the whole view 180° for inverted.
        progress
    }

    var body: some View {
        ZStack {
            // Glass body
            HourglassOutline()
                .stroke(AppTheme.textPrimary.opacity(0.55), lineWidth: 1.5)
                .frame(width: Self.frameWidth, height: Self.frameHeight)
                .background(
                    HourglassOutline()
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

            // Time label
            VStack(spacing: 2) {
                Spacer().frame(height: 4)
                Text(timeString)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.white.opacity(0.85))
                    )
                Spacer()
                if isFinished {
                    Text("Done!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .transition(.opacity.combined(with: .scale))
                        .padding(.bottom, 4)
                }
            }
            .frame(height: Self.frameHeight)
        }
        .frame(width: Self.size, height: Self.size)
        .rotationEffect(.degrees(inverted ? 180 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue(isFinished ? "Done" : timeString)
    }

    // MARK: - Sand fill

    @ViewBuilder
    private var sandLayer: some View {
        let p = max(0, min(1, effectiveProgress))
        // Top chamber: sand level shrinks from full (1) to empty (0) as p goes 0→1.
        // Bottom chamber: sand pile grows from empty (0) to full (1).
        ZStack {
            // Top sand
            TopSandShape(fillFraction: 1 - p)
                .fill(
                    LinearGradient(
                        colors: [Self.sandColor, Self.sandShadow],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            // Bottom sand pile
            BottomSandShape(fillFraction: p)
                .fill(
                    LinearGradient(
                        colors: [Self.sandColor.opacity(0.95), Self.sandShadow],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
        .clipShape(HourglassOutline())
        .animation(.linear(duration: 0.5), value: p)
    }

    // MARK: - Falling grains

    @ViewBuilder
    private var grainsLayer: some View {
        if isRunning && !isPreview && effectiveProgress > 0 && effectiveProgress < 1 && !isFinished {
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
        // Vertical stream from the neck to the bottom pile.
        let centerX = size.width / 2
        let neckY = size.height / 2
        let bottomY = size.height - 12 - (CGFloat(progress) * (size.height / 2 - 20))
        guard bottomY > neckY else { return }

        // Stream line
        let streamRect = CGRect(x: centerX - 0.6, y: neckY,
                                width: 1.2, height: bottomY - neckY)
        ctx.fill(Path(streamRect), with: .color(Self.sandColor.opacity(0.85)))

        // Individual grains falling with a phase offset each
        let grainCount = 6
        for i in 0..<grainCount {
            let phase = Double(i) / Double(grainCount)
            let cycle = (time * 1.4 + phase).truncatingRemainder(dividingBy: 1.0)
            let y = neckY + CGFloat(cycle) * (bottomY - neckY)
            // Slight horizontal wobble for liveliness
            let wobble = sin(time * 6 + Double(i)) * 0.8
            let grain = CGRect(x: centerX - 1 + wobble, y: y - 1, width: 2, height: 2)
            ctx.fill(Path(ellipseIn: grain), with: .color(Self.sandShadow))
        }
    }
}

/// Hourglass outline: two trapezoids meeting at a narrow neck.
private struct HourglassOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let neckWidth: CGFloat = 8
        let neckHeight: CGFloat = 6
        let centerX = rect.midX
        let centerY = rect.midY

        var p = Path()
        // Top-left corner
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top edge
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Top-right down to neck-right (top)
        p.addLine(to: CGPoint(x: centerX + neckWidth / 2, y: centerY - neckHeight / 2))
        // Neck-right (bottom)
        p.addLine(to: CGPoint(x: centerX + neckWidth / 2, y: centerY + neckHeight / 2))
        // Bottom-right
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Bottom edge
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Bottom-left up to neck-left (bottom)
        p.addLine(to: CGPoint(x: centerX - neckWidth / 2, y: centerY + neckHeight / 2))
        // Neck-left (top)
        p.addLine(to: CGPoint(x: centerX - neckWidth / 2, y: centerY - neckHeight / 2))
        p.closeSubpath()
        return p
    }
}

/// Filled sand region in the top chamber. `fillFraction` 1 = full, 0 = empty.
private struct TopSandShape: Shape {
    var fillFraction: CGFloat
    var animatableData: CGFloat {
        get { fillFraction }
        set { fillFraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let f = max(0, min(1, fillFraction))
        let centerY = rect.midY
        // The sand surface drops from the top edge (full) to the neck (empty).
        let surfaceY = rect.minY + (centerY - rect.minY) * (1 - f)
        var p = Path()
        // Top-left to top-right (top edge of glass)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Slide diagonally down the right wall until the surface line height
        let rightX = lerp(rect.maxX, rect.midX, t: (surfaceY - rect.minY) / max(centerY - rect.minY, 1))
        p.addLine(to: CGPoint(x: rightX, y: surfaceY))
        // Slight dip in the middle for a settling-sand look
        p.addLine(to: CGPoint(x: rect.midX, y: surfaceY + 2))
        let leftX = lerp(rect.minX, rect.midX, t: (surfaceY - rect.minY) / max(centerY - rect.minY, 1))
        p.addLine(to: CGPoint(x: leftX, y: surfaceY))
        p.closeSubpath()
        return p
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        return a + (b - a) * clamped
    }
}

/// Filled sand region in the bottom chamber. `fillFraction` 0 = empty, 1 = full.
private struct BottomSandShape: Shape {
    var fillFraction: CGFloat
    var animatableData: CGFloat {
        get { fillFraction }
        set { fillFraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let f = max(0, min(1, fillFraction))
        let centerY = rect.midY
        // The pile surface rises from the bottom edge (empty) to the neck (full).
        let surfaceY = rect.maxY - (rect.maxY - centerY) * f
        var p = Path()
        // Bottom-left to bottom-right
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Up the right wall to the surface
        let rightX = lerp(rect.maxX, rect.midX, t: (rect.maxY - surfaceY) / max(rect.maxY - centerY, 1))
        p.addLine(to: CGPoint(x: rightX, y: surfaceY))
        // Slight mound in the middle (sand pile)
        p.addLine(to: CGPoint(x: rect.midX, y: surfaceY - 3))
        let leftX = lerp(rect.minX, rect.midX, t: (rect.maxY - surfaceY) / max(rect.maxY - centerY, 1))
        p.addLine(to: CGPoint(x: leftX, y: surfaceY))
        p.closeSubpath()
        return p
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        return a + (b - a) * clamped
    }
}
