import SwiftUI

/// Tetris-style timer: random blocks stack inside a square box as time elapses.
/// At 0% the box is empty; at 100% the box is completely filled.
struct TetrisTimerView: View {
    let progress: CGFloat
    let isFinished: Bool
    let timeString: String
    var inverted: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 8 wide × 10 tall grid (80 cells)
    private static let gridW = 8
    private static let gridH = 10
    private static let cellCount = gridW * gridH

    // Box visual constants
    private static let boxSize: CGFloat = 130
    private static let outerCorner: CGFloat = 14
    private static let inset: CGFloat = 6
    private static let cellGap: CGFloat = 1

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

    private var effectiveProgress: CGFloat {
        // Inverted: visually start full and empty out as time elapses.
        inverted ? (1 - progress) : progress
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
    }

    @ViewBuilder
    private var blocksCanvas: some View {
        // floor() so each cell lights up at its true boundary — `.rounded()`
        // would flip the first cell on a half-interval early and fill the
        // box visually before the timer actually reaches zero. The tiny
        // epsilon protects against floating-point shaving at progress=1.0.
        let raw = Double(effectiveProgress) * Double(Self.cellCount) + 1e-6
        let filledCount = min(Self.cellCount, max(0, Int(raw.rounded(.down))))
        Canvas { ctx, size in
            let inset = Self.inset
            let gap = Self.cellGap
            let drawableW = size.width - inset * 2
            let drawableH = size.height - inset * 2
            let cellW = drawableW / CGFloat(Self.gridW)
            let cellH = drawableH / CGFloat(Self.gridH)

            for cellIndex in 0..<Self.cellCount {
                guard Self.rankForCell[cellIndex] < filledCount else { continue }
                let row = cellIndex / Self.gridW
                let col = cellIndex % Self.gridW
                let x = inset + CGFloat(col) * cellW + gap / 2
                let y = inset + CGFloat(row) * cellH + gap / 2
                let rect = CGRect(
                    x: x, y: y,
                    width: cellW - gap, height: cellH - gap
                )
                let block = Path(roundedRect: rect, cornerRadius: 2)
                let color = isFinished ? AppTheme.accent : Self.colorForCell(cellIndex)
                ctx.fill(block, with: .color(color))
                ctx.stroke(block, with: .color(Color.white.opacity(0.25)), lineWidth: 0.8)
            }
        }
        .animation(reduceMotion ? nil : .easeIn(duration: 0.4), value: filledCount)
    }
}
