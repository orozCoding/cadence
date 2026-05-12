import Foundation
import AppKit
import Combine

@MainActor
final class PomodoroTimer: ObservableObject {
    @Published var remaining: TimeInterval = 25 * 60
    @Published var total: TimeInterval = 25 * 60
    @Published var isRunning = false
    @Published var isFinished = false

    private var cancellable: AnyCancellable?

    var progress: Double { total > 0 ? (1 - remaining / total) : 0 }

    var timeString: String {
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "%02d:%02d", m, s)
    }

    func set(minutes: Int) {
        pause()
        total = TimeInterval(minutes * 60)
        remaining = total
        isFinished = false
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard remaining > 0 else { return }
        isRunning = true
        isFinished = false
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        isRunning = false
        cancellable = nil
        FocusTimeStore.shared.flushIfNeeded()
    }

    func reset() {
        pause()
        remaining = total
        isFinished = false
    }

    private func tick() {
        FocusTimeStore.shared.addSecond()
        remaining = max(0, remaining - 1)
        if remaining == 0 {
            pause()
            isFinished = true
            NSSound(named: .init("Glass"))?.play()
        }
    }
}
