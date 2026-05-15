import Foundation

@MainActor
final class FocusTimeStore: ObservableObject {
    static let shared = FocusTimeStore()

    // The only stored data: daily focus seconds keyed by "yyyy-MM-dd".
    @Published private(set) var dailySeconds: [String: Int] = [:]

    private let storageKey = "focusDailySeconds"
    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private var ticksSinceSave = 0
    private let saveInterval = 10

    private init() { load() }

    // MARK: - Timer

    func addSecond() {
        dailySeconds[dayKey(for: Date()), default: 0] += 1
        ticksSinceSave += 1
        if ticksSinceSave >= saveInterval { ticksSinceSave = 0; save() }
    }

    func flushIfNeeded() {
        if ticksSinceSave > 0 { ticksSinceSave = 0; save() }
    }

    // MARK: - Read (all computed from daily data)

    func todaySeconds() -> Int {
        dailySeconds[dayKey(for: Date()), default: 0]
    }

    func weekSeconds(weekStartsOn: Weekday) -> Int {
        let weekStart = Date().startOfWeek(weekStartsOn: weekStartsOn)
        return dailySeconds.reduce(0) { acc, pair in
            guard let date = parseKey(pair.key), date >= weekStart else { return acc }
            return acc + pair.value
        }
    }

    func monthSeconds() -> Int {
        let monthStart = Date().startOfMonth()
        return dailySeconds.reduce(0) { acc, pair in
            guard let date = parseKey(pair.key), date >= monthStart else { return acc }
            return acc + pair.value
        }
    }

    func yearSeconds() -> Int {
        let year = Calendar.current.component(.year, from: Date())
        return dailySeconds.reduce(0) { acc, pair in
            guard let date = parseKey(pair.key),
                  Calendar.current.component(.year, from: date) == year else { return acc }
            return acc + pair.value
        }
    }

    /// All days with recorded focus time, sorted most recent first.
    func sortedDays() -> [(key: String, seconds: Int)] {
        dailySeconds
            .filter { $0.value > 0 }
            .sorted { $0.key > $1.key }
            .map { (key: $0.key, seconds: $0.value) }
    }

    // MARK: - Write

    /// Directly set the focus seconds for a day by its "yyyy-MM-dd" key.
    func setDay(key: String, seconds: Int) {
        if seconds <= 0 {
            dailySeconds.removeValue(forKey: key)
        } else {
            dailySeconds[key] = seconds
        }
        save()
    }

    /// Replace every focus-time entry with the supplied map. Used by the
    /// backup import flow. Non-positive values are filtered out to keep the
    /// stored map sparse (matching `setDay` semantics).
    func replaceAll(_ daily: [String: Int]) {
        dailySeconds = daily.filter { $0.value > 0 }
        ticksSinceSave = 0
        save()
    }

    // MARK: - Helpers

    func dayKey(for date: Date) -> String { df.string(from: date) }
    func parseKey(_ key: String) -> Date? { df.date(from: key) }

    func labelFor(key: String) -> String {
        guard let date = parseKey(key) else { return key }
        if date.isSameDay(as: Date()) { return "Today" }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()),
           date.isSameDay(as: yesterday) { return "Yesterday" }
        return date.dayLabel()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(dailySeconds) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            // Preserve corrupt blob so the next save() doesn't silently overwrite it.
            UserDefaults.standard.set(data, forKey: storageKey + "_backup")
            return
        }
        dailySeconds = decoded
    }
}
