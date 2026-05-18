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
    // Wall-clock seconds the timer has actively run during this session
    // (since the last set / reset / finished-restart). Carried across
    // pause/resume so sub-second remainders are never discarded.
    private var earnedSecondsThisSession: TimeInterval = 0
    // Whole seconds already credited to FocusTimeStore for this session.
    // Invariant while running: equals floor(earnedSecondsThisSession + (now - resumeDate, capped)).
    // Single source of truth — derived from the same wall-clock measurement
    // the countdown uses, so display and stat cannot drift.
    private var creditedSecondsThisSession: Int = 0

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
        // Effective input granularity is 1 second: fractional inputs from the
        // custom-minutes field (e.g. 0.49 min ≈ 29.4 s) are rounded so the
        // display and tick boundaries stay aligned.
        total = max(1, seconds.rounded())
        remaining = total
        beginNewSession()
        isFinished = false
        SoundManager.shared.playTimerSetOrReset()
    }

    func toggle() {
        if isFinished {
            remaining = total
            isFinished = false
            beginNewSession()
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
            creditEarnedSeconds(now: now)
            let runEarned = currentRunEarned(now: now)
            earnedSecondsThisSession += runEarned
            remaining = max(0, remainingAtResume - runEarned)
        }
        isRunning = false
        cancellable = nil
        FocusTimeStore.shared.flushIfNeeded()
    }

    func reset() {
        pause()
        remaining = total
        beginNewSession()
        isFinished = false
        SoundManager.shared.playTimerSetOrReset()
    }

    /// Stop and reset the timer to its configured `total` without playing
    /// the reset sound. Used when a backup import / rollback is about to
    /// overwrite the focus store — keeping the pre-import session paused
    /// would let a later resume drift the freshly-imported focus total.
    func prepareForDataReplacement() {
        pause()
        remaining = total
        isFinished = false
    }

    /// Credit any whole seconds of in-flight focus time to `FocusTimeStore`
    /// without pausing or otherwise disturbing a running session. Used by
    /// the backup export path so a snapshot taken mid-tick reflects the
    /// same focus total a `pause()` would credit a moment later.
    ///
    /// Mirrors the credit logic inside `tick()` and `pause()`. Sub-second
    /// remainder stays in `focusAccumulator` and will be credited by the
    /// next regular tick.
    func creditInFlightFocusTime() {
        if isRunning {
            let now = Date()
            focusAccumulator += min(now.timeIntervalSince(lastTickDate), 2)
            let wholeSeconds = Int(focusAccumulator)
            if wholeSeconds > 0 {
                for _ in 0..<wholeSeconds { FocusTimeStore.shared.addSecond() }
                focusAccumulator -= TimeInterval(wholeSeconds)
            }
            lastTickDate = now
        }
        FocusTimeStore.shared.flushIfNeeded()
    }

    private func tick() {
        let now = Date()
        creditEarnedSeconds(now: now)
        let runElapsed = now.timeIntervalSince(resumeDate)
        remaining = max(0, remainingAtResume - runElapsed)
        if remaining == 0 {
            isFinished = true   // set before pause() so no subscriber sees isRunning=false + isFinished=false
            pause()
            SoundManager.shared.playTimerFinished(sound: AppSettings.shared.timerFinishSound)
            sendTimerFinishedNotification()
        }
    }

    private func beginNewSession() {
        earnedSecondsThisSession = 0
        creditedSecondsThisSession = 0
    }

    /// Wall-clock seconds elapsed in the current run, clamped to the planned
    /// duration for this run. Clamping means a long sleep/wake gap or runloop
    /// stall can never credit past what the timer was set to count.
    private func currentRunEarned(now: Date) -> TimeInterval {
        max(0, min(now.timeIntervalSince(resumeDate), remainingAtResume))
    }

    /// Credits any whole-second focus time owed as of `now`. Idempotent —
    /// safe to call repeatedly within the same run (e.g. tick then pause).
    private func creditEarnedSeconds(now: Date) {
        guard isRunning else { return }
        let totalEarned = earnedSecondsThisSession + currentRunEarned(now: now)
        let earnedWhole = Int(totalEarned)  // floor; non-negative
        let toCredit = earnedWhole - creditedSecondsThisSession
        if toCredit > 0 {
            for _ in 0..<toCredit { FocusTimeStore.shared.addSecond() }
            creditedSecondsThisSession = earnedWhole
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
