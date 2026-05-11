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

    // MARK: - Filtered views

    func tasks(forDay date: Date) -> [CadenceTask] {
        tasks.filter { task in
            guard let d = task.dayDeadline else { return false }
            return d.isSameDay(as: date)
        }
    }

    func tasks(forWeek weekStart: Date, weekStartsOn: Weekday) -> [CadenceTask] {
        tasks.filter { task in
            guard let w = task.weekStart else { return false }
            return w.isSameWeek(as: weekStart, weekStartsOn: weekStartsOn)
        }
    }

    func tasks(forMonth monthStart: Date) -> [CadenceTask] {
        tasks.filter { task in
            guard let m = task.monthStart else { return false }
            return m.isSameMonth(as: monthStart)
        }
    }

    func tasks(forYear year: Int) -> [CadenceTask] {
        tasks.filter { $0.yearDeadline == year }
    }

    // MARK: - Distinct period keys

    func distinctDays() -> [Date] {
        let days = tasks.compactMap { $0.dayDeadline?.startOfDay() }
        return Array(Set(days)).sorted()
    }

    func distinctWeeks(weekStartsOn: Weekday) -> [Date] {
        let weeks = tasks.compactMap { $0.weekStart?.startOfWeek(weekStartsOn: weekStartsOn) }
        return Array(Set(weeks)).sorted()
    }

    func distinctMonths() -> [Date] {
        let months = tasks.compactMap { $0.monthStart?.startOfMonth() }
        return Array(Set(months)).sorted()
    }

    func distinctYears() -> [Int] {
        let years = tasks.compactMap { $0.yearDeadline }
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
