import SwiftUI

enum TaskPeriod: Equatable, Hashable {
    case day(Date)
    case week(Date)
    case month(Date)
    case year(Int)

    var title: String {
        switch self {
        case .day(let d):
            return d.isSameDay(as: Date()) ? "Today" : d.dayLabel()
        case .week(let s):
            return s.weekLabel()
        case .month(let s):
            return s.monthLabel()
        case .year(let y):
            return String(y)
        }
    }
}

struct PeriodTasksView: View {
    let period: TaskPeriod
    @Binding var selectedTask: CadenceTask?
    @Binding var showNewTask: Bool

    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings

    private var pending: [CadenceTask] {
        allTasks.filter { !$0.isDone }
    }
    private var done: [CadenceTask] {
        allTasks.filter { $0.isDone }
    }

    private var allTasks: [CadenceTask] {
        switch period {
        case .day(let d):
            return store.tasks(forDay: d)
        case .week(let s):
            return store.tasks(forWeek: s, weekStartsOn: settings.weekStartsOn)
        case .month(let s):
            return store.tasks(forMonth: s)
        case .year(let y):
            return store.tasks(forYear: y)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TasksHeader(title: period.title, showNewTask: $showNewTask)
            Divider().background(AppTheme.divider)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    if !pending.isEmpty {
                        Section {
                            ForEach(pending) { task in
                                TaskRowView(
                                    task: task,
                                    onTap: { withAnimation { selectedTask = task } },
                                    onToggle: { store.toggle(task) }
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 2)
                            }
                        } header: {
                            SectionHeader(label: "To Do", count: pending.count)
                        }
                    }

                    if !done.isEmpty {
                        Section {
                            ForEach(done) { task in
                                TaskRowView(
                                    task: task,
                                    onTap: { withAnimation { selectedTask = task } },
                                    onToggle: { store.toggle(task) }
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 2)
                            }
                        } header: {
                            SectionHeader(label: "Done", count: done.count)
                        }
                    }

                    if allTasks.isEmpty {
                        EmptyStateView(message: "No tasks for \(period.title).\nClick + to add one.")
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }
}
