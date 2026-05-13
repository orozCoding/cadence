import Foundation

struct CadenceTask: Identifiable, Codable, Equatable {
    let id: UUID
    var folderId: UUID
    var title: String
    var body: String
    var isDone: Bool
    var createdAt: Date
    var sortOrder: Int              // global fallback order (used when no period key exists)
    var periodSortKeys: [String: Int]  // per-period ordering keyed by TaskPeriod.storageKey

    // Independent deadline levels
    var dayDeadline: Date?
    var weekStart: Date?    // start-of-week date
    var monthStart: Date?   // start-of-month date
    var yearDeadline: Int?

    init(
        id: UUID = UUID(),
        folderId: UUID = .generalFolderID,
        title: String,
        body: String = "",
        isDone: Bool = false,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        periodSortKeys: [String: Int] = [:],
        dayDeadline: Date? = nil,
        weekStart: Date? = nil,
        monthStart: Date? = nil,
        yearDeadline: Int? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.title = title
        self.body = body
        self.isDone = isDone
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.periodSortKeys = periodSortKeys
        self.dayDeadline = dayDeadline
        self.weekStart = weekStart
        self.monthStart = monthStart
        self.yearDeadline = yearDeadline
    }

    // Custom decoder: existing tasks without folderId default to General
    private enum CodingKeys: String, CodingKey {
        case id, folderId, title, body, isDone, createdAt, sortOrder, periodSortKeys
        case dayDeadline, weekStart, monthStart, yearDeadline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        folderId        = try c.decodeIfPresent(UUID.self, forKey: .folderId) ?? .generalFolderID
        title           = try c.decode(String.self, forKey: .title)
        body            = try c.decode(String.self, forKey: .body)
        isDone          = try c.decode(Bool.self, forKey: .isDone)
        createdAt       = try c.decode(Date.self, forKey: .createdAt)
        sortOrder       = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        periodSortKeys  = try c.decodeIfPresent([String: Int].self, forKey: .periodSortKeys) ?? [:]
        dayDeadline     = try c.decodeIfPresent(Date.self, forKey: .dayDeadline)
        weekStart       = try c.decodeIfPresent(Date.self, forKey: .weekStart)
        monthStart      = try c.decodeIfPresent(Date.self, forKey: .monthStart)
        yearDeadline    = try c.decodeIfPresent(Int.self, forKey: .yearDeadline)
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

        let currentWeekStart = Date().startOfWeek(weekStartsOn: weekStartsOn)
        if let w = weekStart, w < currentWeekStart {
            errors.append("Week deadline cannot be in the past.")
        }

        let currentMonthStart = Date().startOfMonth()
        if let m = monthStart, m < currentMonthStart {
            errors.append("Month deadline cannot be in the past.")
        }

        let currentYear = Calendar.current.component(.year, from: Date())
        if let y = year, y < currentYear {
            errors.append("Year deadline cannot be in the past.")
        }

        // Adjacent-level checks
        if let d = day, let w = weekStart {
            if w < d.startOfWeek(weekStartsOn: weekStartsOn) {
                errors.append("Week deadline must contain or follow the day deadline.")
            }
        }
        if let w = weekStart, let m = monthStart {
            if m < w.startOfMonth() {
                errors.append("Month deadline must contain or follow the week deadline.")
            }
        }
        if let m = monthStart, let y = year {
            if y < Calendar.current.component(.year, from: m) {
                errors.append("Year deadline must match or follow the month deadline's year.")
            }
        }

        // Non-adjacent checks when intermediate levels are skipped
        if let d = day, weekStart == nil, let m = monthStart {
            if m < d.startOfMonth() {
                errors.append("Month deadline must contain or follow the day deadline.")
            }
        }
        if let d = day, weekStart == nil, monthStart == nil, let y = year {
            if y < Calendar.current.component(.year, from: d) {
                errors.append("Year deadline must match or follow the day deadline's year.")
            }
        }
        if let w = weekStart, monthStart == nil, let y = year {
            if y < Calendar.current.component(.year, from: w) {
                errors.append("Year deadline must match or follow the week deadline's year.")
            }
        }

        return errors
    }
}
