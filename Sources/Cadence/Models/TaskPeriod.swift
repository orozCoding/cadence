import Foundation

enum TaskPeriod: Equatable, Hashable {
    case day(Date)
    case week(Date)
    case month(Date)
    case year(Int)

    func titleFor(weekStartsOn: Weekday, today: Date = Date()) -> String {
        switch self {
        case .day(let d):   return d.fullDayLabel(today: today)
        case .week(let s):  return s.weekLabel(weekStartsOn: weekStartsOn, today: today)
        case .month(let s): return s.monthLabel(today: today)
        case .year(let y):  return y.yearLabel(today: today)
        }
    }

    // Stable string key used to isolate sort orders per period view.
    // Calendar-component based so keys survive timezone changes.
    var storageKey: String {
        let cal = Calendar.current
        switch self {
        case .day(let d):
            let y = cal.component(.year, from: d)
            let mo = cal.component(.month, from: d)
            let dy = cal.component(.day, from: d)
            return "d:\(y)-\(mo)-\(dy)"
        case .week(let s):
            let y = cal.component(.year, from: s)
            let mo = cal.component(.month, from: s)
            let dy = cal.component(.day, from: s)
            return "w:\(y)-\(mo)-\(dy)"
        case .month(let s):
            let y = cal.component(.year, from: s)
            let mo = cal.component(.month, from: s)
            return "m:\(y)-\(mo)"
        case .year(let y):
            return "y:\(y)"
        }
    }
}
