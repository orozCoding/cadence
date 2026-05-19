import SwiftUI

/// Jogger-style timer: a running figure traverses a horizontal track,
/// reaching the finish flag exactly when the timer ends.
struct JoggerTimerView: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    let isRunning: Bool
    var inverted: Bool = false
    var isPreview: Bool = false

    private static let canvasW: CGFloat = 130
    private static let canvasH: CGFloat = 130
    private static let trackY: CGFloat = 92          // runner foot Y inside the canvas
    private static let trackInset: CGFloat = 14      // left/right padding
    private static let figureSize: CGFloat = 32
    private static let bobRate: CGFloat = 9          // rad/sec for the running cycle

    // Bob phase anchoring — matches the GlassTimerCircle pause/resume pattern.
    // When running: phase = phaseAtStart + (now - runStartDate) * bobRate.
    // When paused:  phase is frozen at frozenBobPhase so the figure holds its pose.
    @State private var frozenBobPhase: CGFloat = 0
    @State private var runStartDate: Date = .now
    @State private var phaseAtStart: CGFloat = 0

    private var trackLeft: CGFloat { Self.trackInset }
    private var trackRight: CGFloat { Self.canvasW - Self.trackInset }
    private var trackLength: CGFloat { trackRight - trackLeft }

    private var runnerX: CGFloat {
        let p = max(0, min(1, progress))
        return inverted
            ? trackRight - p * trackLength
            : trackLeft  + p * trackLength
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Time label up top
            VStack(spacing: 1) {
                Text(timeString)
                    .font(.system(size: 22, weight: .thin, design: .monospaced))
                    .foregroundStyle(isFinished ? AppTheme.accent : AppTheme.textPrimary)
                    .contentTransition(.numericText())
                if isFinished {
                    Text("Done!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(width: Self.canvasW, alignment: .center)
            .padding(.top, 6)

            // Track line
            Rectangle()
                .fill(AppTheme.divider)
                .frame(width: trackLength, height: 2)
                .offset(x: trackLeft, y: Self.trackY + 2)

            // Dashed pace markers
            DashedTrack(length: trackLength)
                .stroke(AppTheme.divider.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                .frame(width: trackLength, height: 1)
                .offset(x: trackLeft, y: Self.trackY + 8)

            // Start marker (left side, original direction)
            startMarker
                .offset(x: inverted ? trackRight - 2 : trackLeft - 2,
                        y: Self.trackY - 14)

            // Finish flag (right side, original direction)
            finishFlag
                .offset(x: inverted ? trackLeft - 8 : trackRight - 8,
                        y: Self.trackY - 22)

            // Runner figure
            runner
                .offset(x: runnerX - Self.figureSize / 2,
                        y: Self.trackY - Self.figureSize + 4)
        }
        .frame(width: Self.canvasW, height: Self.canvasH)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue(isFinished ? "Done" : timeString)
        .onAppear {
            guard !isPreview else { return }
            runStartDate = .now
            phaseAtStart = frozenBobPhase
        }
        .onChange(of: isRunning) { _, running in
            guard !isPreview else { return }
            if running {
                // Resume: re-anchor wall clock, keep accumulated phase.
                runStartDate = .now
                phaseAtStart = frozenBobPhase
            } else {
                // Pause: freeze the current phase so the figure holds its pose.
                let elapsed = CGFloat(Date().timeIntervalSince(runStartDate))
                frozenBobPhase = phaseAtStart + elapsed * Self.bobRate
            }
        }
        .onChange(of: progress) { _, newProgress in
            // Reset the bob anchor when the timer is fully reset (progress=0).
            guard !isPreview, newProgress == 0 else { return }
            frozenBobPhase = 0
            phaseAtStart = 0
        }
    }

    // MARK: - Runner

    @ViewBuilder
    private var runner: some View {
        if isRunning && !isPreview {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                let elapsed = CGFloat(context.date.timeIntervalSince(runStartDate))
                let phase = phaseAtStart + elapsed * Self.bobRate
                runnerFigure(bobPhase: phase)
            }
        } else {
            // Paused / preview: hold the captured phase so the figure stays in
            // place rather than snapping back to a neutral pose.
            runnerFigure(bobPhase: isPreview ? 0 : frozenBobPhase)
        }
    }

    @ViewBuilder
    private func runnerFigure(bobPhase: CGFloat) -> some View {
        let bob = sin(bobPhase) * 2.5
        Image(systemName: "figure.run")
            .font(.system(size: Self.figureSize, weight: .semibold))
            .foregroundStyle(isFinished ? AppTheme.accent : AppTheme.accentDark)
            .scaleEffect(x: inverted ? -1 : 1, y: 1)
            .shadow(color: AppTheme.accent.opacity(0.25), radius: 3, x: 0, y: 1)
            .offset(y: bob)
            .animation(.linear(duration: 0.5), value: progress)
    }

    // MARK: - Markers

    @ViewBuilder
    private var startMarker: some View {
        Rectangle()
            .fill(AppTheme.textTertiary)
            .frame(width: 2, height: 18)
    }

    @ViewBuilder
    private var finishFlag: some View {
        ZStack(alignment: .bottomLeading) {
            // Flagpole
            Rectangle()
                .fill(AppTheme.textPrimary)
                .frame(width: 2, height: 26)
            // Checkered flag (simplified)
            CheckeredFlag()
                .frame(width: 16, height: 11)
                .offset(x: 2, y: -15)
        }
    }
}

/// Horizontal dashed line used as a pace track under the runner.
private struct DashedTrack: Shape {
    let length: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: length, y: rect.midY))
        return p
    }
}

/// Tiny 2-row checkered flag rectangle.
private struct CheckeredFlag: View {
    var body: some View {
        let cols = 4
        let rows = 2
        GeometryReader { geo in
            let cw = geo.size.width / CGFloat(cols)
            let ch = geo.size.height / CGFloat(rows)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.white)
                ForEach(0..<rows, id: \.self) { r in
                    ForEach(0..<cols, id: \.self) { c in
                        if (r + c).isMultiple(of: 2) {
                            Rectangle()
                                .fill(AppTheme.textPrimary)
                                .frame(width: cw, height: ch)
                                .offset(x: CGFloat(c) * cw, y: CGFloat(r) * ch)
                        }
                    }
                }
            }
            .overlay(Rectangle().stroke(AppTheme.textPrimary, lineWidth: 0.5))
        }
    }
}
