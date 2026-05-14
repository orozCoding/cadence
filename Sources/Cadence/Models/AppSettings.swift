import Foundation
import Combine

enum TimerStyle: String, CaseIterable, Identifiable {
    case glassy  = "glassy"
    case minimal = "minimal"
    case orbit   = "orbit"
    case pulse   = "pulse"
    case radiate = "radiate"
    case neon    = "neon"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glassy:   return "Glassy"
        case .minimal:  return "Minimal"
        case .orbit:    return "Orbit"
        case .pulse:    return "Pulse"
        case .radiate:  return "Radiate"
        case .neon:     return "Neon"
        }
    }

    var description: String {
        switch self {
        case .glassy:   return "Liquid glass fill"
        case .minimal:  return "Clean arc stroke"
        case .orbit:    return "Rocket with fire trail"
        case .pulse:    return "Sonar pulse waves"
        case .radiate:  return "Rotating spoke ring"
        case .neon:     return "Electric plasma arc"
        }
    }
}

/// Visual-only setting: controls which way each style's animation renders.
/// It does not affect timer calculation — `remaining` and `progress` are always
/// direction-independent. Changing it mid-session is safe and takes effect immediately.
enum TimerDirection: String, CaseIterable, Identifiable {
    case original = "original"
    case inverted = "inverted"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .inverted: return "Inverted"
        }
    }
}

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
    @Published var timerStyle: TimerStyle {
        didSet { save() }
    }
    @Published var timerDirection: TimerDirection {
        didSet { save() }
    }
    @Published var currentDate: Date = Calendar.current.startOfDay(for: Date())

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let raw = UserDefaults.standard.integer(forKey: "weekStartsOn")
        weekStartsOn = Weekday(rawValue: raw) ?? .monday

        let soundRaw = UserDefaults.standard.string(forKey: "timerFinishSound") ?? ""
        timerFinishSound = TimerFinishSound(rawValue: soundRaw) ?? .standard

        let styleRaw = UserDefaults.standard.string(forKey: "timerStyle") ?? ""
        timerStyle = TimerStyle(rawValue: styleRaw) ?? .glassy

        let directionRaw = UserDefaults.standard.string(forKey: "timerDirection") ?? ""
        timerDirection = TimerDirection(rawValue: directionRaw) ?? .original

        let refreshDate: (Notification) -> Void = { [weak self] _ in
            self?.currentDate = Calendar.current.startOfDay(for: Date())
        }
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink(receiveValue: refreshDate)
                .store(in: &cancellables)
        }
    }

    private func save() {
        UserDefaults.standard.set(weekStartsOn.rawValue, forKey: "weekStartsOn")
        UserDefaults.standard.set(timerFinishSound.rawValue, forKey: "timerFinishSound")
        UserDefaults.standard.set(timerStyle.rawValue, forKey: "timerStyle")
        UserDefaults.standard.set(timerDirection.rawValue, forKey: "timerDirection")
    }
}
