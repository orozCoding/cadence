import Foundation

extension Date {
    func startOfDay(calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: self)
    }

    // Store calendar deadlines at noon local time so timezone changes up to ±12h
    // won't shift the stored date into an adjacent calendar day when reloaded.
    func noonLocal(calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: self) ?? self
    }

    func startOfWeek(weekStartsOn: Weekday = .monday, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = weekStartsOn.calendarValue
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return cal.date(from: components) ?? self
    }

    func startOfMonth(calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }

    func year(calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: self)
    }

    func endOfWeek(weekStartsOn: Weekday = .monday, calendar: Calendar = .current) -> Date {
        let start = startOfWeek(weekStartsOn: weekStartsOn, calendar: calendar)
        return calendar.date(byAdding: .day, value: 7, to: start) ?? self
    }

    func endOfMonth(calendar: Calendar = .current) -> Date {
        let start = startOfMonth(calendar: calendar)
        return calendar.date(byAdding: .month, value: 1, to: start) ?? self
    }

    func isSameDay(as other: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(self, inSameDayAs: other)
    }

    func isSameWeek(as other: Date, weekStartsOn: Weekday = .monday, calendar: Calendar = .current) -> Bool {
        startOfWeek(weekStartsOn: weekStartsOn, calendar: calendar) ==
            other.startOfWeek(weekStartsOn: weekStartsOn, calendar: calendar)
    }

    func isSameMonth(as other: Date, calendar: Calendar = .current) -> Bool {
        startOfMonth(calendar: calendar) == other.startOfMonth(calendar: calendar)
    }

    func weekLabel(weekStartsOn: Weekday = .monday) -> String {
        let start = startOfWeek(weekStartsOn: weekStartsOn)
        var cal = Calendar.current
        cal.firstWeekday = weekStartsOn.calendarValue
        guard let end = cal.date(byAdding: .day, value: 6, to: start) else { return "" }
        let startFmt = DateFormatter()
        startFmt.dateFormat = "MMM d"
        let endFmt = DateFormatter()
        // Include month name if week crosses a month boundary
        let crossesMonth = cal.component(.month, from: start) != cal.component(.month, from: end)
        endFmt.dateFormat = crossesMonth ? "MMM d, yyyy" : "d, yyyy"
        return "\(startFmt.string(from: start)) – \(endFmt.string(from: end))"
    }

    func monthLabel() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: self)
    }

    func dayLabel() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        return fmt.string(from: self)
    }
}

enum Weekday: Int, CaseIterable, Codable {
    case monday = 2
    case sunday = 1

    var label: String {
        switch self {
        case .monday: return "Monday"
        case .sunday: return "Sunday"
        }
    }

    var calendarValue: Int { rawValue }
}
