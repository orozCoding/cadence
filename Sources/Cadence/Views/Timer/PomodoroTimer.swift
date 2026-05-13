import Foundation
import AppKit
import Combine

@MainActor
final class PomodoroTimer: ObservableObject {
    static let shared = PomodoroTimer()

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
        set(seconds: TimeInterval(minutes * 60))
    }

    func set(seconds: TimeInterval) {
        pause()
        total = max(1, seconds.rounded())
        remaining = total
        isFinished = false
        SoundManager.shared.playTimerSetOrReset()
    }

    func toggle() {
        if isRunning {
            SoundManager.shared.playTimerPause()
            pause()
        } else {
            start()
        }
    }

    func start() {
        guard remaining > 0 else { return }
        isRunning = true
        isFinished = false
        SoundManager.shared.playTimerStart()
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
        SoundManager.shared.playTimerSetOrReset()
    }

    private func tick() {
        FocusTimeStore.shared.addSecond()
        remaining = max(0, remaining - 1)
        if remaining == 0 {
            pause()
            isFinished = true
            SoundManager.shared.playTimerFinished(sound: AppSettings.shared.timerFinishSound)
        }
    }
}
