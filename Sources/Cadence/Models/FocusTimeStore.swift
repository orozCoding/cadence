import Foundation

@MainActor
final class FocusTimeStore: ObservableObject {
    static let shared = FocusTimeStore()

    // Timer accumulates here (daily buckets, keyed "yyyy-MM-dd")
    @Published private(set) var dailySeconds: [String: Int] = [:]

    // Independent manual adjustments per period (do not cascade into each other)
    @Published private var manualToday: [String: Int] = [:]   // dayKey → delta on top of raw
    @Published private var manualWeek: [String: Int] = [:]    // weekStartKey → delta (excludes today adj)
    @Published private var manualMonth: [String: Int] = [:]   // monthStartKey → delta (excludes today adj)

    private let storageKey       = "focusDailySeconds"
    private let manualTodayKey   = "focusManualToday"
    private let manualWeekKey    = "focusManualWeek"
    private let manualMonthKey   = "focusManualMonth"

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var ticksSinceSave = 0
    private let saveInterval = 10

    private init() { load() }

    // MARK: - Timer

    func addSecond() {
        let key = dayKey(for: Date())
        dailySeconds[key, default: 0] += 1
        ticksSinceSave += 1
        if ticksSinceSave >= saveInterval { ticksSinceSave = 0; save() }
    }

    func flushIfNeeded() {
        if ticksSinceSave > 0 { ticksSinceSave = 0; save() }
    }

    // MARK: - Read
    // Editing "today" propagates to week+month (today is part of both).
    // Editing "week" or "month" affects only that aggregate.

    func todaySeconds() -> Int {
        let key = dayKey(for: Date())
        return max(0, dailySeconds[key, default: 0] + (manualToday[key] ?? 0))
    }

    func weekSeconds(weekStartsOn: Weekday) -> Int {
        max(0, rawWeekSum(weekStartsOn: weekStartsOn)
            + (manualToday[dayKey(for: Date())] ?? 0)
            + (manualWeek[weekKey(for: Date(), weekStartsOn: weekStartsOn)] ?? 0))
    }

    func monthSeconds() -> Int {
        max(0, rawMonthSum()
            + (manualToday[dayKey(for: Date())] ?? 0)
            + (manualMonth[monthKey(for: Date())] ?? 0))
    }

    // MARK: - Write (each affects only its own period)

    func setToday(seconds: Int) {
        let key = dayKey(for: Date())
        manualToday[key] = seconds - dailySeconds[key, default: 0]
        save()
    }

    func setWeek(to seconds: Int, weekStartsOn: Weekday) {
        let key = weekKey(for: Date(), weekStartsOn: weekStartsOn)
        manualWeek[key] = (manualWeek[key] ?? 0) + (seconds - weekSeconds(weekStartsOn: weekStartsOn))
        save()
    }

    func setMonth(to seconds: Int) {
        let key = monthKey(for: Date())
        manualMonth[key] = (manualMonth[key] ?? 0) + (seconds - monthSeconds())
        save()
    }

    // MARK: - Private helpers

    private func rawWeekSum(weekStartsOn: Weekday) -> Int {
        let weekStart = Date().startOfWeek(weekStartsOn: weekStartsOn)
        return dailySeconds.reduce(0) { acc, pair in
            guard let date = parseKey(pair.key) else { return acc }
            return date >= weekStart ? acc + pair.value : acc
        }
    }

    private func rawMonthSum() -> Int {
        let monthStart = Date().startOfMonth()
        return dailySeconds.reduce(0) { acc, pair in
            guard let date = parseKey(pair.key) else { return acc }
            return date >= monthStart ? acc + pair.value : acc
        }
    }

    private func dayKey(for date: Date) -> String { df.string(from: date) }
    private func parseKey(_ key: String) -> Date? { df.date(from: key) }
    private func weekKey(for date: Date, weekStartsOn: Weekday) -> String {
        df.string(from: date.startOfWeek(weekStartsOn: weekStartsOn))
    }
    private func monthKey(for date: Date) -> String { df.string(from: date.startOfMonth()) }

    // MARK: - Persistence

    private func save() {
        let ud = UserDefaults.standard
        func enc<T: Encodable>(_ v: T, key: String) {
            if let d = try? JSONEncoder().encode(v) { ud.set(d, forKey: key) }
        }
        enc(dailySeconds, key: storageKey)
        enc(manualToday,  key: manualTodayKey)
        enc(manualWeek,   key: manualWeekKey)
        enc(manualMonth,  key: manualMonthKey)
    }

    private func load() {
        let ud = UserDefaults.standard
        func dec<T: Decodable>(_ key: String) -> T? {
            guard let d = ud.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(T.self, from: d)
        }
        dailySeconds = dec(storageKey)     ?? [:]
        manualToday  = dec(manualTodayKey) ?? [:]
        manualWeek   = dec(manualWeekKey)  ?? [:]
        manualMonth  = dec(manualMonthKey) ?? [:]
    }
}
