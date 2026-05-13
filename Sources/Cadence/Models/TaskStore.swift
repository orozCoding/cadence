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
        t.sortOrder = (tasks.map(\.sortOrder).max() ?? -1) + 1
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
        save()
    }

    func deleteAll(inFolder folderId: UUID) {
        tasks.removeAll { $0.folderId == folderId }
        save()
    }

    // MARK: - Filtered views (folder-scoped)

    func tasks(forDay date: Date, folderId: UUID) -> [CadenceTask] {
        tasks.filter { task in
            task.folderId == folderId &&
            task.dayDeadline.map { $0.isSameDay(as: date) } == true
        }.sortedByOrder(periodKey: TaskPeriod.day(date).storageKey)
    }

    func tasks(forWeek weekStart: Date, weekStartsOn: Weekday, folderId: UUID) -> [CadenceTask] {
        tasks.filter { task in
            task.folderId == folderId &&
            task.weekStart.map { $0.isSameWeek(as: weekStart, weekStartsOn: weekStartsOn) } == true
        }.sortedByOrder(periodKey: TaskPeriod.week(weekStart).storageKey)
    }

    func tasks(forMonth monthStart: Date, folderId: UUID) -> [CadenceTask] {
        tasks.filter { task in
            task.folderId == folderId &&
            task.monthStart.map { $0.isSameMonth(as: monthStart) } == true
        }.sortedByOrder(periodKey: TaskPeriod.month(monthStart).storageKey)
    }

    func tasks(forYear year: Int, folderId: UUID) -> [CadenceTask] {
        tasks.filter { $0.folderId == folderId && $0.yearDeadline == year }
             .sortedByOrder(periodKey: TaskPeriod.year(year).storageKey)
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
