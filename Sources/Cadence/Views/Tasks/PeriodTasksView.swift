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
    @EnvironmentObject var folderStore: FolderStore

    private var allTasks: [CadenceTask] {
        let fid = folderStore.activeFolder.id
        switch period {
        case .day(let d):   return store.tasks(forDay: d, folderId: fid)
        case .week(let s):  return store.tasks(forWeek: s, weekStartsOn: settings.weekStartsOn, folderId: fid)
        case .month(let s): return store.tasks(forMonth: s, folderId: fid)
        case .year(let y):  return store.tasks(forYear: y, folderId: fid)
        }
    }

    private var ordered: [CadenceTask] {
        allTasks.filter { !$0.isDone } + allTasks.filter { $0.isDone }
    }

    var body: some View {
        VStack(spacing: 0) {
            TasksHeader(title: period.titleFor(weekStartsOn: settings.weekStartsOn), showNewTask: $showNewTask)
            Divider().background(AppTheme.divider)

            if allTasks.isEmpty {
                EmptyStateView(message: "No tasks for \(period.titleFor(weekStartsOn: settings.weekStartsOn)).\nClick + to add one.")
                    .frame(maxHeight: .infinity)
            } else {
                TaskListView(
                    tasks: ordered,
                    onTap: { task in withAnimation { selectedTask = task } },
                    onToggle: { task in store.toggle(task) }
                )
            }
        }
    }
}
