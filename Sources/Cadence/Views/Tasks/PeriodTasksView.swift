import SwiftUI

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

struct PeriodTasksView: View {
    let period: TaskPeriod
    @Binding var selectedTask: CadenceTask?
    @Binding var showNewTask: Bool

    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings

    private var allTasks: [CadenceTask] {
        switch period {
        case .day(let d):   return store.tasks(forDay: d)
        case .week(let s):  return store.tasks(forWeek: s, weekStartsOn: settings.weekStartsOn)
        case .month(let s): return store.tasks(forMonth: s)
        case .year(let y):  return store.tasks(forYear: y)
        }
    }

    // Single sorted array: pending first, then done.
    private var ordered: [CadenceTask] {
        allTasks.filter { !$0.isDone } + allTasks.filter { $0.isDone }
    }

    private var pendingCount: Int { ordered.filter { !$0.isDone }.count }
    private var doneCount: Int    { ordered.filter {  $0.isDone }.count }

    var body: some View {
        VStack(spacing: 0) {
            TasksHeader(title: period.titleFor(weekStartsOn: settings.weekStartsOn), showNewTask: $showNewTask)
            Divider().background(AppTheme.divider)

            if allTasks.isEmpty {
                EmptyStateView(message: "No tasks for \(period.titleFor(weekStartsOn: settings.weekStartsOn)).\nClick + to add one.")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if pendingCount > 0 {
                            SectionHeader(label: "To Do", count: pendingCount)
                        }

                        ForEach(ordered) { task in
                            // Insert the "Done" section header before the first done task.
                            if task.id == ordered.first(where: { $0.isDone })?.id {
                                SectionHeader(label: "Done", count: doneCount)
                                    .padding(.top, pendingCount > 0 ? 8 : 0)
                                    .transition(.opacity)
                            }

                            TaskRowView(
                                task: task,
                                onTap: { withAnimation { selectedTask = task } },
                                onToggle: { store.toggle(task) }
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 2)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.vertical, 12)
                    .animation(.easeInOut(duration: 0.28), value: ordered.map(\.id))
                }
            }
        }
    }
}
