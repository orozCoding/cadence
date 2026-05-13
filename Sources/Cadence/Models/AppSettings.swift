import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var weekStartsOn: Weekday {
        didSet { save() }
    }
    @Published var currentDate: Date = Calendar.current.startOfDay(for: Date())

    private let key = "weekStartsOn"
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let raw = UserDefaults.standard.integer(forKey: "weekStartsOn")
        weekStartsOn = Weekday(rawValue: raw) ?? .monday

        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.currentDate = Calendar.current.startOfDay(for: Date())
            }
            .store(in: &cancellables)
    }

    private func save() {
        UserDefaults.standard.set(weekStartsOn.rawValue, forKey: key)
    }
}
