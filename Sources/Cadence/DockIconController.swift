import AppKit
import Combine

@MainActor
final class DockIconController {
    static let shared = DockIconController()

    private var animationTimer: Timer?
    private var cancellable: AnyCancellable?
    private var angle: Double = 0
    private var baseIcon: NSImage?

    private init() {}

    func start() {
        baseIcon = NSApplication.shared.applicationIconImage?.copy() as? NSImage
        cancellable = PomodoroTimer.shared.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                if running { self?.startSpinning() } else { self?.stopSpinning() }
            }
    }

    private func startSpinning() {
        guard animationTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        animationTimer = t
    }

    private func stopSpinning() {
        animationTimer?.invalidate()
        animationTimer = nil
        angle = 0
        // nil tells macOS to restore the bundle icon reliably
        NSApplication.shared.applicationIconImage = nil
    }

    private func tick() {
        // One full revolution every 15 seconds at 12 fps (2° per tick)
        angle = (angle + 2.0).truncatingRemainder(dividingBy: 360)
        guard let base = baseIcon, let icon = makeAnimatedIcon(base, angle: angle) else { return }
        NSApplication.shared.applicationIconImage = icon
    }

    // Draws the static background/frame first, then overlays the icon rotated and
    // clipped to an inner circle — only the ring design spins, not the outer background.
    private func makeAnimatedIcon(_ image: NSImage, angle degrees: Double) -> NSImage? {
        let size = NSSize(width: 256, height: 256)
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

        // Layer 1: static full icon (background frame stays fixed)
        image.draw(in: NSRect(origin: .zero, size: size))

        // Layer 2: rotated icon, clipped to inner circle (captures all ring design)
        let clipRadius = size.width * 0.40   // 102 px for 256×256; leaves ~26 px background frame
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(
            x: size.width / 2 - clipRadius,
            y: size.height / 2 - clipRadius,
            width: clipRadius * 2,
            height: clipRadius * 2
        ))
        ctx.clip()
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.rotate(by: CGFloat(-degrees) * .pi / 180)
        ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        image.draw(in: NSRect(origin: .zero, size: size))
        ctx.restoreGState()

        return result
    }
}
