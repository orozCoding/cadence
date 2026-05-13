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
        baseIcon = NSApplication.shared.applicationIconImage
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
        NSApplication.shared.applicationIconImage = baseIcon
    }

    private func tick() {
        // One full revolution every 8 seconds at 12 fps
        angle = (angle + 3.75).truncatingRemainder(dividingBy: 360)
        guard let base = baseIcon, let icon = rotated(base, by: angle) else { return }
        NSApplication.shared.applicationIconImage = icon
    }

    private func rotated(_ image: NSImage, by degrees: Double) -> NSImage? {
        let size = NSSize(width: 256, height: 256)
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.rotate(by: CGFloat(-degrees) * .pi / 180)
        ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        image.draw(in: NSRect(origin: .zero, size: size))
        return result
    }
}
