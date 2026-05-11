import Foundation
import Combine

final class PomodoroTimer: ObservableObject {
    enum Phase: String, CaseIterable, Identifiable {
        case focus = "Focus"
        case shortBreak = "Short Break"
        case longBreak = "Long Break"

        var id: String { rawValue }
        var label: String { rawValue }

        var duration: TimeInterval {
            switch self {
            case .focus: return 25 * 60
            case .shortBreak: return 5 * 60
            case .longBreak: return 15 * 60
            }
        }
    }

    @Published var phase: Phase = .focus { didSet { reset() } }
    @Published var remaining: TimeInterval = Phase.focus.duration
    @Published var isRunning = false

    private var cancellable: AnyCancellable?

    var timeString: String {
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "%02d:%02d", m, s)
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        isRunning = true
        cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        isRunning = false
        cancellable = nil
    }

    func reset() {
        pause()
        remaining = phase.duration
    }

    private func tick() {
        if remaining > 0 {
            remaining -= 1
        } else {
            pause()
        }
    }
}
