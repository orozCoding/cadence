import Foundation
import AppKit
import Combine
import UserNotifications

@MainActor
final class PomodoroTimer: ObservableObject {
    static let shared = PomodoroTimer()

    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published var total: TimeInterval = 25 * 60
    @Published var isRunning = false
    @Published var isFinished = false

    private var cancellable: AnyCancellable?
    private var resumeDate: Date = .now
    private var remainingAtResume: TimeInterval = 25 * 60
    private var lastTickDate: Date = .now
    // Sub-second carry-over: prevents credit loss when ticks fire early (<1 s intervals)
    private var focusAccumulator: TimeInterval = 0

    var progress: Double { total > 0 ? (1 - remaining / total) : 0 }

    var timeString: String {
        // Finished: always show 00:00.
        // Running/paused: ceil so the display stays at N until a full second has elapsed,
        // and guard ≥ 1 so a sub-second fractional remainder never shows 00:00 prematurely.
        if isFinished { return "00:00" }
        let totalSecs = max(1, Int(ceil(remaining)))
        return String(format: "%02d:%02d", totalSecs / 60, totalSecs % 60)
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
        focusAccumulator = 0
        isRunning = true
        isFinished = false
        SoundManager.shared.playTimerStart()
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        if isRunning {
            let now = Date()
            // Flush in-flight time since the last tick before discarding the accumulator
            focusAccumulator += min(now.timeIntervalSince(lastTickDate), 2)
            let wholeSeconds = Int(focusAccumulator)
            if wholeSeconds > 0 {
                for _ in 0..<wholeSeconds { FocusTimeStore.shared.addSecond() }
            }
            let elapsed = now.timeIntervalSince(resumeDate)
            remaining = max(0, remainingAtResume - elapsed)
        }
        focusAccumulator = 0
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
        // Accumulate elapsed time (capped at 2 s to ignore sleep gaps).
        // Using an accumulator instead of Int truncation prevents credit loss when
        // the publisher fires slightly early (< 1 s) — e.g. two 0.6 s ticks correctly
        // credit 1 second rather than 0+0 = 0.
        focusAccumulator += min(tickElapsed, 2)
        let wholeSeconds = Int(focusAccumulator)
        if wholeSeconds > 0 {
            for _ in 0..<wholeSeconds { FocusTimeStore.shared.addSecond() }
            focusAccumulator -= TimeInterval(wholeSeconds)
        }
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
