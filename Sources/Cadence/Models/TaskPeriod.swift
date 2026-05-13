import Foundation

enum TaskPeriod: Equatable, Hashable {
    case day(Date)
    case week(Date)
    case month(Date)
    case year(Int)

    var title: String { titleFor(weekStartsOn: .monday) }

    func titleFor(weekStartsOn: Weekday) -> String {
        switch self {
        case .day(let d):   return d.isSameDay(as: Date()) ? "Today" : d.dayLabel()
        case .week(let s):  return s.weekLabel(weekStartsOn: weekStartsOn)
        case .month(let s): return s.monthLabel()
        case .year(let y):  return String(y)
        }
    }
}
