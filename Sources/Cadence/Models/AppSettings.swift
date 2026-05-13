import Foundation
import Combine

enum TimerFinishSound: String, CaseIterable, Identifiable {
    case standard = "timer_finished"
    case variant2 = "timer_finished_2"
    case variant3 = "timer_finished_3"
    case song = "timer_finished_song"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Classic"
        case .variant2: return "Alert 2"
        case .variant3: return "Alert 3"
        case .song: return "Song"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var weekStartsOn: Weekday {
        didSet { save() }
    }

    @Published var timerFinishSound: TimerFinishSound {
        didSet { save() }
    }

    @Published var soundsMuted: Bool {
        didSet { save() }
    }

    private init() {
        let raw = UserDefaults.standard.integer(forKey: "weekStartsOn")
        weekStartsOn = Weekday(rawValue: raw) ?? .monday

        let soundRaw = UserDefaults.standard.string(forKey: "timerFinishSound") ?? ""
        timerFinishSound = TimerFinishSound(rawValue: soundRaw) ?? .standard

        soundsMuted = UserDefaults.standard.bool(forKey: "soundsMuted")
    }

    private func save() {
        UserDefaults.standard.set(weekStartsOn.rawValue, forKey: "weekStartsOn")
        UserDefaults.standard.set(timerFinishSound.rawValue, forKey: "timerFinishSound")
        UserDefaults.standard.set(soundsMuted, forKey: "soundsMuted")
    }
}
