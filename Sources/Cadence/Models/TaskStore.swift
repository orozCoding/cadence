import Foundation
import Combine

@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    // No didSet save — load() assigns directly without triggering a save.
    // All mutating methods call save() explicitly.
    @Published var tasks: [CadenceTask] = []

    private let storageKey = "cadence_tasks"
    private let backupKey  = "cadence_tasks_backup"

    private init() {
        load()
    }

    // MARK: - CRUD

    func add(_ task: CadenceTask) {
        var t = task
        // Use max of ALL sort values (global sortOrder + all periodSortKeys) so the
        // new task's sortOrder is always higher than any existing key, ensuring it
        // appears at the bottom of every period view regardless of manual reorder history.
        let maxPeriodKey = tasks.flatMap { Array($0.periodSortKeys.values) }.max() ?? -1
        let maxSortOrder = tasks.map(\.sortOrder).max() ?? -1
        t.sortOrder = max(maxPeriodKey, maxSortOrder) + 1
        tasks.append(t)
        save()
    }

    func update(_ task: CadenceTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx] = task
        save()
    }

    func delete(_ task: CadenceTask) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    func toggle(_ task: CadenceTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].isDone.toggle()
        save()
    }

    func setDone(_ taskId: UUID, isDone: Bool) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].isDone = isDone
        save()
    }

    // Record the display order for a specific period view.
    // Uses per-period keys so reordering in one view doesn't affect others.
    func reorder(taskIds: [UUID], periodKey: String) {
        for (index, id) in taskIds.enumerated() {
            if let idx = tasks.firstIndex(where: { $0.id == id }) {
                tasks[idx].periodSortKeys[periodKey] = index
            }
        }
        save()
    }

    // Update the deadline for the given period level.
    // - Finer-grained levels are cleared (they may no longer fall inside the new period).
    // - Coarser-grained levels that were already set are updated to contain the new period,
    //   keeping deadline combinations internally consistent.
    // - All dates are stored at noon-local to match the invariant used by NewTaskSheet.
    func moveToPeriod(taskId: UUID, period: TaskPeriod, weekStartsOn: Weekday = .monday) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }

        // Snapshot all period storage keys before mutations so we can detect which
        // changed and prune them after — handles both same-level and cross-level moves.
        let preDayKey  = tasks[idx].dayDeadline.map   { TaskPeriod.day($0).storageKey }
        let preWeekKey = tasks[idx].weekStart.map     { TaskPeriod.week($0).storageKey }
        let preMoKey   = tasks[idx].monthStart.map    { TaskPeriod.month($0).storageKey }
        let preYearKey = tasks[idx].yearDeadline.map  { TaskPeriod.year($0).storageKey }

        // No-op only when the task is at exactly the target granularity — not just contained within it.
        // A day-level task dropped on its parent week bucket must still clear the dayDeadline.
        let alreadyThere: Bool
        switch period {
        case .day(let d):
            alreadyThere = tasks[idx].dayDeadline.map { $0.isSameDay(as: d) } == true
        case .week(let s):
            alreadyThere = tasks[idx].weekStart.map { $0.isSameWeek(as: s, weekStartsOn: weekStartsOn) } == true
                && tasks[idx].dayDeadline == nil
        case .month(let s):
            alreadyThere = tasks[idx].monthStart.map { $0.isSameMonth(as: s) } == true
                && tasks[idx].weekStart == nil && tasks[idx].dayDeadline == nil
        case .year(let y):
            alreadyThere = tasks[idx].yearDeadline == y
                && tasks[idx].monthStart == nil && tasks[idx].weekStart == nil && tasks[idx].dayDeadline == nil
        }
        guard !alreadyThere else { return }

        switch period {
        case .day(let d):
            tasks[idx].dayDeadline = d.noonLocal()
            if tasks[idx].weekStart != nil {
                tasks[idx].weekStart = d.startOfWeek(weekStartsOn: weekStartsOn).noonLocal()
            }
            if tasks[idx].monthStart != nil {
                tasks[idx].monthStart = d.startOfMonth().noonLocal()
            }
            if tasks[idx].yearDeadline != nil {
                tasks[idx].yearDeadline = d.year()
            }
        case .week(let s):
            tasks[idx].weekStart = s.noonLocal()
            tasks[idx].dayDeadline = nil
            if tasks[idx].monthStart != nil {
                tasks[idx].monthStart = s.startOfMonth().noonLocal()
            }
            if tasks[idx].yearDeadline != nil {
                tasks[idx].yearDeadline = s.year()
            }
        case .month(let s):
            tasks[idx].monthStart = s.noonLocal()
            tasks[idx].weekStart = nil
            tasks[idx].dayDeadline = nil
            if tasks[idx].yearDeadline != nil {
                tasks[idx].yearDeadline = s.year()
            }
        case .year(let y):
            tasks[idx].yearDeadline = y
            tasks[idx].monthStart = nil
            tasks[idx].weekStart = nil
            tasks[idx].dayDeadline = nil
        }

        // Remove sort keys for any period level that changed or was cleared by the move.
        // Comparing pre/post snapshots covers all directions: same-level, finer-to-coarser,
        // and coarser-to-finer (e.g., a day move that also changes the containing week).
        let postDayKey  = tasks[idx].dayDeadline.map   { TaskPeriod.day($0).storageKey }
        let postWeekKey = tasks[idx].weekStart.map     { TaskPeriod.week($0).storageKey }
        let postMoKey   = tasks[idx].monthStart.map    { TaskPeriod.month($0).storageKey }
        let postYearKey = tasks[idx].yearDeadline.map  { TaskPeriod.year($0).storageKey }

        for (old, new) in [(preDayKey, postDayKey), (preWeekKey, postWeekKey),
                           (preMoKey, postMoKey),   (preYearKey, postYearKey)] {
            if let old, old != new {
                tasks[idx].periodSortKeys.removeValue(forKey: "td:\(old)")
                tasks[idx].periodSortKeys.removeValue(forKey: "dn:\(old)")
            }
        }

        // Stamp a sort key for the destination section so the task lands at the end
        // rather than falling back to global sortOrder and causing unexpected reshuffles.
        let prefix = tasks[idx].isDone ? "dn:" : "td:"
        let destKey = prefix + period.storageKey
        let maxEffective = tasks
            .filter { $0.id != taskId }
            .map { $0.periodSortKeys[destKey] ?? $0.sortOrder }
            .max() ?? -1
        tasks[idx].periodSortKeys[destKey] = maxEffective + 1
        save()
    }

    func deleteAll(inFolder folderId: UUID) {
        tasks.removeAll { $0.folderId == folderId }
        save()
    }

    // MARK: - Filtered views (folder-scoped)

    func tasks(forDay date: Date, folderId: UUID) -> [CadenceTask] {
        splitSorted(
            tasks.filter { $0.folderId == folderId && $0.dayDeadline.map { $0.isSameDay(as: date) } == true },
            periodKey: TaskPeriod.day(date).storageKey
        )
    }

    func tasks(forWeek weekStart: Date, weekStartsOn: Weekday, folderId: UUID) -> [CadenceTask] {
        splitSorted(
            tasks.filter { $0.folderId == folderId && $0.weekStart.map { $0.isSameWeek(as: weekStart, weekStartsOn: weekStartsOn) } == true },
            periodKey: TaskPeriod.week(weekStart).storageKey
        )
    }

    func tasks(forMonth monthStart: Date, folderId: UUID) -> [CadenceTask] {
        splitSorted(
            tasks.filter { $0.folderId == folderId && $0.monthStart.map { $0.isSameMonth(as: monthStart) } == true },
            periodKey: TaskPeriod.month(monthStart).storageKey
        )
    }

    func tasks(forYear year: Int, folderId: UUID) -> [CadenceTask] {
        splitSorted(
            tasks.filter { $0.folderId == folderId && $0.yearDeadline == year },
            periodKey: TaskPeriod.year(year).storageKey
        )
    }

    // Sort todos and dones using section-scoped keys ("td:" / "dn:") to prevent
    // index collisions between the two sections when tasks move between them.
    private func splitSorted(_ all: [CadenceTask], periodKey: String) -> [CadenceTask] {
        all.filter { !$0.isDone }.sortedByOrder(periodKey: "td:\(periodKey)")
        + all.filter {  $0.isDone }.sortedByOrder(periodKey: "dn:\(periodKey)")
    }

    // MARK: - Distinct period keys (folder-scoped)

    func distinctDays(folderId: UUID) -> [Date] {
        let days = tasks.filter { $0.folderId == folderId }.compactMap { $0.dayDeadline?.startOfDay() }
        return Array(Set(days)).sorted()
    }

    func distinctWeeks(weekStartsOn: Weekday, folderId: UUID) -> [Date] {
        let weeks = tasks.filter { $0.folderId == folderId }
            .compactMap { $0.weekStart?.startOfWeek(weekStartsOn: weekStartsOn) }
        return Array(Set(weeks)).sorted()
    }

    func distinctMonths(folderId: UUID) -> [Date] {
        let months = tasks.filter { $0.folderId == folderId }.compactMap { $0.monthStart?.startOfMonth() }
        return Array(Set(months)).sorted()
    }

    func distinctYears(folderId: UUID) -> [Int] {
        let years = tasks.filter { $0.folderId == folderId }.compactMap { $0.yearDeadline }
        return Array(Set(years)).sorted()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }

        if let saved = try? JSONDecoder().decode([CadenceTask].self, from: data) {
            tasks = saved  // Direct assignment — no didSet, no auto-save
            return
        }

        // One malformed record would hide all valid tasks. Attempt per-item recovery.
        // Always back up the original blob first so no data is silently lost.
        UserDefaults.standard.set(data, forKey: backupKey)
        if let rawItems = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let decoder = JSONDecoder()
            let recovered = rawItems.compactMap { item -> CadenceTask? in
                guard let itemData = try? JSONSerialization.data(withJSONObject: item) else { return nil }
                return try? decoder.decode(CadenceTask.self, from: itemData)
            }
            if !recovered.isEmpty {
                tasks = recovered
                return
            }
        }
    }
}

private extension Array where Element == CadenceTask {
    // Sort by the per-period key if one exists, falling back to global sortOrder,
    // then createdAt as a stable tiebreaker.
    func sortedByOrder(periodKey: String) -> [CadenceTask] {
        sorted {
            let ao = $0.periodSortKeys[periodKey] ?? $0.sortOrder
            let bo = $1.periodSortKeys[periodKey] ?? $1.sortOrder
            if ao != bo { return ao < bo }
            return $0.createdAt < $1.createdAt
        }
    }
}
