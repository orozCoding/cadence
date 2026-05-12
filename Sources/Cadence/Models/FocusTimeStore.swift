import Foundation

@MainActor
final class FocusTimeStore: ObservableObject {
    static let shared = FocusTimeStore()

    // "yyyy-MM-dd" -> accumulated seconds on that day
    @Published private(set) var dailySeconds: [String: Int] = [:]

    private let storageKey = "focusDailySeconds"

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() { load() }

    func addSecond() {
        let key = dayKey(for: Date())
        dailySeconds[key, default: 0] += 1
        save()
    }

    func todaySeconds() -> Int {
        dailySeconds[dayKey(for: Date()), default: 0]
    }

    func weekSeconds(weekStartsOn: Weekday) -> Int {
        let weekStart = Date().startOfWeek(weekStartsOn: weekStartsOn)
        return dailySeconds.reduce(0) { acc, pair in
            guard let date = parseKey(pair.key) else { return acc }
            return date >= weekStart ? acc + pair.value : acc
        }
    }

    func monthSeconds() -> Int {
        let monthStart = Date().startOfMonth()
        return dailySeconds.reduce(0) { acc, pair in
            guard let date = parseKey(pair.key) else { return acc }
            return date >= monthStart ? acc + pair.value : acc
        }
    }

    func setToday(seconds: Int) {
        dailySeconds[dayKey(for: Date())] = max(0, seconds)
        save()
    }

    func setWeek(to seconds: Int, weekStartsOn: Weekday) {
        let key = dayKey(for: Date())
        let todayVal = dailySeconds[key, default: 0]
        let otherDays = weekSeconds(weekStartsOn: weekStartsOn) - todayVal
        dailySeconds[key] = max(0, seconds - otherDays)
        save()
    }

    func setMonth(to seconds: Int) {
        let key = dayKey(for: Date())
        let todayVal = dailySeconds[key, default: 0]
        let otherDays = monthSeconds() - todayVal
        dailySeconds[key] = max(0, seconds - otherDays)
        save()
    }

    private func dayKey(for date: Date) -> String { formatter.string(from: date) }
    private func parseKey(_ key: String) -> Date? { formatter.date(from: key) }

    private func save() {
        guard let data = try? JSONEncoder().encode(dailySeconds) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return }
        dailySeconds = decoded
    }
}
