import Foundation

struct CadenceTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var body: String
    var isDone: Bool
    var createdAt: Date

    // Independent deadline levels
    var dayDeadline: Date?
    var weekStart: Date?    // start-of-week date
    var monthStart: Date?   // start-of-month date
    var yearDeadline: Int?

    init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        isDone: Bool = false,
        createdAt: Date = Date(),
        dayDeadline: Date? = nil,
        weekStart: Date? = nil,
        monthStart: Date? = nil,
        yearDeadline: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isDone = isDone
        self.createdAt = createdAt
        self.dayDeadline = dayDeadline
        self.weekStart = weekStart
        self.monthStart = monthStart
        self.yearDeadline = yearDeadline
    }

    // MARK: - Validation

    static func validate(
        day: Date?,
        weekStart: Date?,
        monthStart: Date?,
        year: Int?,
        weekStartsOn: Weekday
    ) -> [String] {
        var errors: [String] = []
        let today = Date().startOfDay()

        if let d = day, d < today {
            errors.append("Day deadline cannot be in the past.")
        }

        if let d = day, let w = weekStart {
            let taskWeek = d.startOfWeek(weekStartsOn: weekStartsOn)
            if w < taskWeek {
                errors.append("Week deadline must contain or follow the day deadline.")
            }
        }

        if let w = weekStart, let m = monthStart {
            let weekMonth = w.startOfMonth()
            if m < weekMonth {
                errors.append("Month deadline must contain or follow the week deadline.")
            }
        }

        if let m = monthStart, let y = year {
            let monthYear = Calendar.current.component(.year, from: m)
            if y < monthYear {
                errors.append("Year deadline must match or follow the month deadline's year.")
            }
        }

        return errors
    }
}
