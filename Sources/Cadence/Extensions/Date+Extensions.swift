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

    // Sidebar label: abbreviated month OK ("Monday, May 12"), relative labels for today/yesterday/tomorrow
    func dayLabel() -> String {
        let today = Date()
        let cal = Calendar.current
        if isSameDay(as: today) { return "Today" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: today)),
           isSameDay(as: yesterday) { return "Yesterday" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: today)),
           isSameDay(as: tomorrow) { return "Tomorrow" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return fmt.string(from: self)
    }

    // Center column label: full weekday and full month name, no abbreviations
    func fullDayLabel() -> String {
        let today = Date()
        let cal = Calendar.current
        if isSameDay(as: today) { return "Today" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: today)),
           isSameDay(as: yesterday) { return "Yesterday" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: today)),
           isSameDay(as: tomorrow) { return "Tomorrow" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d"
        return fmt.string(from: self)
    }

    func weekLabel(weekStartsOn: Weekday = .monday) -> String {
        let today = Date()
        let cal = Calendar.current
        let thisWeekStart = today.startOfWeek(weekStartsOn: weekStartsOn)
        let selfWeekStart = startOfWeek(weekStartsOn: weekStartsOn)
        if selfWeekStart == thisWeekStart { return "This Week" }
        if let last = cal.date(byAdding: .day, value: -7, to: thisWeekStart),
           selfWeekStart == last { return "Last Week" }
        if let next = cal.date(byAdding: .day, value: 7, to: thisWeekStart),
           selfWeekStart == next { return "Next Week" }
        var wcal = cal
        wcal.firstWeekday = weekStartsOn.calendarValue
        guard let end = wcal.date(byAdding: .day, value: 6, to: selfWeekStart) else { return "" }
        let startFmt = DateFormatter()
        startFmt.dateFormat = "MMMM d"
        let endFmt = DateFormatter()
        let crossesMonth = wcal.component(.month, from: selfWeekStart) != wcal.component(.month, from: end)
        endFmt.dateFormat = crossesMonth ? "MMMM d, yyyy" : "d, yyyy"
        return "\(startFmt.string(from: selfWeekStart)) – \(endFmt.string(from: end))"
    }

    func monthLabel() -> String {
        let today = Date()
        let cal = Calendar.current
        if isSameMonth(as: today) { return "This Month" }
        let thisMonthStart = today.startOfMonth()
        if let last = cal.date(byAdding: .month, value: -1, to: thisMonthStart),
           isSameMonth(as: last) { return "Last Month" }
        if let next = cal.date(byAdding: .month, value: 1, to: thisMonthStart),
           isSameMonth(as: next) { return "Next Month" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: self)
    }
}

extension Int {
    func yearLabel() -> String {
        let currentYear = Calendar.current.component(.year, from: Date())
        switch self {
        case currentYear: return "This Year"
        case currentYear - 1: return "Last Year"
        case currentYear + 1: return "Next Year"
        default: return String(self)
        }
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
