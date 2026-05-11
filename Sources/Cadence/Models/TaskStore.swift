import Foundation
import Combine

@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    @Published var tasks: [CadenceTask] = [] {
        didSet { save() }
    }

    private let storageKey = "cadence_tasks"

    private init() {
        load()
    }

    // MARK: - CRUD

    func add(_ task: CadenceTask) {
        tasks.append(task)
    }

    func update(_ task: CadenceTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx] = task
    }

    func delete(_ task: CadenceTask) {
        tasks.removeAll { $0.id == task.id }
    }

    func toggle(_ task: CadenceTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].isDone.toggle()
    }

    func deleteAll(inFolder folderId: UUID) {
        tasks.removeAll { $0.folderId == folderId }
    }

    // MARK: - Filtered views (folder-scoped)

    func tasks(forDay date: Date, folderId: UUID) -> [CadenceTask] {
        tasks.filter { task in
            task.folderId == folderId &&
            task.dayDeadline.map { $0.isSameDay(as: date) } == true
        }
    }

    func tasks(forWeek weekStart: Date, weekStartsOn: Weekday, folderId: UUID) -> [CadenceTask] {
        tasks.filter { task in
            task.folderId == folderId &&
            task.weekStart.map { $0.isSameWeek(as: weekStart, weekStartsOn: weekStartsOn) } == true
        }
    }

    func tasks(forMonth monthStart: Date, folderId: UUID) -> [CadenceTask] {
        tasks.filter { task in
            task.folderId == folderId &&
            task.monthStart.map { $0.isSameMonth(as: monthStart) } == true
        }
    }

    func tasks(forYear year: Int, folderId: UUID) -> [CadenceTask] {
        tasks.filter { $0.folderId == folderId && $0.yearDeadline == year }
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
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([CadenceTask].self, from: data)
        else { return }
        tasks = saved
    }
}
