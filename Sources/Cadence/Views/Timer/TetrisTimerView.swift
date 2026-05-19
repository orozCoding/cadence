import SwiftUI

/// Tetris-style timer: random blocks stack inside a square box as time elapses.
/// At 0% the box is empty; at 100% the box is completely filled.
struct TetrisTimerView: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    var inverted: Bool = false
    var isPreview: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Per-cell drop start times. `nil` means the cell is currently unfilled.
    /// When a cell becomes filled, the entry is set to the moment the drop
    /// animation should start; cells already settled have entries far enough
    /// in the past that elapsed > dropDuration.
    @State private var cellFillTimes: [Date?] = Array(repeating: nil, count: TetrisTimerView.cellCount)

    // 8 wide × 10 tall grid (80 cells)
    private static let gridW = 8
    private static let gridH = 10
    private static let cellCount = gridW * gridH

    // Box visual constants
    private static let boxSize: CGFloat = 130
    private static let outerCorner: CGFloat = 14
    private static let inset: CGFloat = 6
    private static let cellGap: CGFloat = 1

    // Drop animation tuning
    private static let dropDuration: TimeInterval = 0.45
    /// How far above the cell's final position the block starts. Larger =
    /// more dramatic fall.
    private static let fallHeight: CGFloat = 140
    /// Delay between simultaneous drops so a batch of newly-filled cells
    /// cascades rather than all landing on the same frame.
    private static let dropStagger: TimeInterval = 0.04

    private static let palette: [Color] = [
        Color(hex: "#2B8FD4"), // accent blue
        Color(hex: "#5AAEE0"), // accent light
        Color(hex: "#1A6FA8"), // accent dark
        Color(hex: "#F5C24D"), // amber
        Color(hex: "#7DC76B"), // green
        Color(hex: "#E07A5F"), // coral
        Color(hex: "#9C6ADE"), // violet
    ]

    // Splitmix32-style finalizer — deterministic per-index hash.
    // Avoids a stateful RNG so we don't need a helper struct in this file.
    private static func hashed(_ index: Int, salt: UInt32) -> UInt32 {
        var h = UInt32(truncatingIfNeeded: index) &* 2654435769
        h ^= salt
        h ^= h >> 16
        h = h &* 0x85ebca6b
        h ^= h >> 13
        h = h &* 0xc2b2ae35
        h ^= h >> 16
        return h
    }

    private static func colorForCell(_ index: Int) -> Color {
        palette[Int(hashed(index, salt: 0xC0FFEE) % UInt32(palette.count))]
    }

    /// Position of `cellIndex` in the fill sequence — lower means filled earlier.
    /// Bottom rows (largest row index) fill first; within each row, a pseudo-random
    /// per-cell rank decides column order.
    private static func fillOrder(_ cellIndex: Int) -> Int {
        let row = cellIndex / gridW
        // Within-row rank: use the hash modulo a large stride so collisions are rare;
        // ties still fill in column order which is fine visually.
        let withinRowRank = Int(hashed(cellIndex, salt: 0xBADC0DE) & 0xFFFFFF)
        // Lower fill order ⇒ filled earlier. Bottom rows must be smallest, so
        // we use (gridH - 1 - row) as the row-band weight.
        return (gridH - 1 - row) * 1_000_000_000 + withinRowRank
    }

    /// Precomputed rank for each cell, normalized to 0..<cellCount.
    private static let rankForCell: [Int] = {
        let pairs = (0..<cellCount).map { ($0, fillOrder($0)) }
        let sorted = pairs.sorted { $0.1 < $1.1 }
        var rank = Array(repeating: 0, count: cellCount)
        for (rankIndex, pair) in sorted.enumerated() {
            rank[pair.0] = rankIndex
        }
        return rank
    }()

    /// Inverse mapping: `cellAtRank[rank]` is the cellIndex that fills at that
    /// position in the sequence. Used to find which cells just became filled
    /// when `filledCount` increases.
    private static let cellAtRank: [Int] = {
        var result = Array(repeating: 0, count: cellCount)
        for (cellIndex, rank) in rankForCell.enumerated() {
            result[rank] = cellIndex
        }
        return result
    }()

    private var effectiveProgress: CGFloat {
        // Inverted: visually start full and empty out as time elapses.
        inverted ? (1 - progress) : progress
    }

    private var filledCount: Int {
        // floor() so each cell lights up at its true boundary. The tiny
        // epsilon protects against floating-point shaving at progress=1.0.
        let raw = Double(effectiveProgress) * Double(Self.cellCount) + 1e-6
        return min(Self.cellCount, max(0, Int(raw.rounded(.down))))
    }

    var body: some View {
        ZStack {
            // Outer playfield box
            RoundedRectangle(cornerRadius: Self.outerCorner)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.contentBackground, AppTheme.sidebarBackground],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Self.outerCorner)
                        .stroke(AppTheme.divider, lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)

            // Grid of blocks
            blocksCanvas

            // Time label with a translucent pill behind it for readability
            VStack(spacing: 2) {
                Text(timeString)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.78))
                    )
                if isFinished {
                    Text("Done!")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .frame(width: Self.boxSize, height: Self.boxSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer")
        .accessibilityValue(isFinished ? "Done" : timeString)
        .onAppear {
            // Snap to the current filled state without animating (e.g. when the
            // user comes back to Tetris from another style mid-session).
            syncFillTimes(animateNew: false)
        }
        .onChange(of: progress) { _, _ in
            // New progress tick — animate freshly-revealed cells dropping in.
            // Skip the drop animation in preview rows and under Reduce Motion.
            syncFillTimes(animateNew: !reduceMotion && !isPreview)
        }
    }

    /// Reconciles `cellFillTimes` against the current `filledCount`. Cells
    /// crossing into the filled range get a (possibly future) drop start time;
    /// cells leaving the filled range (timer reset) are cleared.
    private func syncFillTimes(animateNew: Bool) {
        let target = filledCount
        let now = Date()
        var next = cellFillTimes

        // Clear cells that are no longer filled (timer reset / inverted swap).
        for rank in target..<Self.cellCount {
            let cellIdx = Self.cellAtRank[rank]
            if next[cellIdx] != nil { next[cellIdx] = nil }
        }
        // Assign drop times to cells that just became filled, staggered so a
        // batch landing in the same tick cascades rather than colliding.
        var staggerSlot = 0
        for rank in 0..<target {
            let cellIdx = Self.cellAtRank[rank]
            guard next[cellIdx] == nil else { continue }
            if animateNew {
                next[cellIdx] = now.addingTimeInterval(TimeInterval(staggerSlot) * Self.dropStagger)
                staggerSlot += 1
            } else {
                // Settle instantly: push the start time far enough into the past
                // that elapsed > dropDuration on the next frame.
                next[cellIdx] = now.addingTimeInterval(-Self.dropDuration - 1)
            }
        }
        cellFillTimes = next
    }

    @ViewBuilder
    private var blocksCanvas: some View {
        // TimelineView drives per-frame Canvas redraws so each cell can
        // interpolate its Y offset during its drop. Paused under Reduce
        // Motion and in preview rows — cells render at their settled
        // positions in those cases.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || isPreview)) { context in
            Canvas { ctx, size in
                drawBlocks(ctx: ctx, size: size, now: context.date)
            }
        }
    }

    private func drawBlocks(ctx: GraphicsContext, size: CGSize, now: Date) {
        let inset = Self.inset
        let gap = Self.cellGap
        let drawableW = size.width - inset * 2
        let drawableH = size.height - inset * 2
        let cellW = drawableW / CGFloat(Self.gridW)
        let cellH = drawableH / CGFloat(Self.gridH)

        for cellIndex in 0..<Self.cellCount {
            guard let fillTime = cellFillTimes[cellIndex] else { continue }
            let elapsed = now.timeIntervalSince(fillTime)
            // Staggered cells with a future start time are not yet falling.
            if elapsed < 0 { continue }
            let t = reduceMotion ? 1.0 : min(1.0, elapsed / Self.dropDuration)
            // Ease-out (decelerating fall) — feels like landing under gravity.
            let eased = 1 - pow(1 - t, 2)
            let yOffset = (1 - eased) * -Self.fallHeight

            let row = cellIndex / Self.gridW
            let col = cellIndex % Self.gridW
            let x = inset + CGFloat(col) * cellW + gap / 2
            let y = inset + CGFloat(row) * cellH + gap / 2 + yOffset
            let rect = CGRect(x: x, y: y, width: cellW - gap, height: cellH - gap)
            let block = Path(roundedRect: rect, cornerRadius: 2)
            let color = isFinished ? AppTheme.accent : Self.colorForCell(cellIndex)
            ctx.fill(block, with: .color(color))
            ctx.stroke(block, with: .color(Color.white.opacity(0.25)), lineWidth: 0.8)
        }
    }
}
