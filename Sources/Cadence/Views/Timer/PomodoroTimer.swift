import Foundation
import AppKit
import Combine
import UserNotifications

@MainActor
final class PomodoroTimer: ObservableObject {
    static let shared = PomodoroTimer()

    @Published var remaining: TimeInterval = 25 * 60
    @Published var total: TimeInterval = 25 * 60
    @Published var isRunning = false
    @Published var isFinished = false

    private var cancellable: AnyCancellable?
    private var resumeDate: Date = .now
    private var remainingAtResume: TimeInterval = 25 * 60
    private var lastTickDate: Date = .now

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
        if isFinished {
            remaining = total
            isFinished = false
            start()
            return
        }
        if isRunning {
            SoundManager.shared.playTimerPause()
            pause()
        } else {
            start()
        }
    }

    func start() {
        guard remaining > 0 else { return }
        // Request permission on first timer start so the prompt appears in context.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { print("[Cadence] Notification auth error: \(error)") }
        }
        resumeDate = .now
        remainingAtResume = remaining
        lastTickDate = .now
        isRunning = true
        isFinished = false
        SoundManager.shared.playTimerStart()
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        if isRunning {
            let elapsed = Date().timeIntervalSince(resumeDate)
            remaining = max(0, remainingAtResume - elapsed)
        }
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
        let now = Date()
        let tickElapsed = now.timeIntervalSince(lastTickDate)
        lastTickDate = now
        // Cap focus-time credit at 2s per tick so Mac sleep gaps don't inflate focus stats.
        let focusSeconds = min(Int(tickElapsed.rounded()), 2)
        for _ in 0..<focusSeconds { FocusTimeStore.shared.addSecond() }
        let elapsed = now.timeIntervalSince(resumeDate)
        remaining = max(0, remainingAtResume - elapsed)
        if remaining == 0 {
            pause()
            isFinished = true
            SoundManager.shared.playTimerFinished(sound: AppSettings.shared.timerFinishSound)
            sendTimerFinishedNotification()
        }
    }

    private func sendTimerFinishedNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Time's Up!"
        content.subtitle = formattedDuration(total)
        // No notification sound — SoundManager already handles audio feedback.
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[Cadence] Failed to schedule notification: \(error)") }
        }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        if remainingSeconds == 0 {
            return totalMinutes == 1 ? "1-minute session complete" : "\(totalMinutes)-minute session complete"
        }
        return "\(totalMinutes) min \(remainingSeconds) sec session complete"
    }
}
