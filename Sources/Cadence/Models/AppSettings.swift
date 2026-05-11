import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var weekStartsOn: Weekday {
        didSet { save() }
    }

    private let key = "weekStartsOn"

    private init() {
        let raw = UserDefaults.standard.integer(forKey: "weekStartsOn")
        weekStartsOn = Weekday(rawValue: raw) ?? .monday
    }

    private func save() {
        UserDefaults.standard.set(weekStartsOn.rawValue, forKey: key)
    }
}
