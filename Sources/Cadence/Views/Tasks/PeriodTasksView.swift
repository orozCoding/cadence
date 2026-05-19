import SwiftUI

enum TaskPeriod: Equatable, Hashable {
    case day(Date)
    case week(Date)
    case month(Date)
    case year(Int)

    var title: String { titleFor(weekStartsOn: .monday, today: Date()) }

    func titleFor(weekStartsOn: Weekday, today: Date = Date()) -> String {
        switch self {
        case .day(let d):   return d.fullDayLabel(today: today)
        case .week(let s):  return s.weekLabel(weekStartsOn: weekStartsOn, today: today)
        case .month(let s): return s.monthLabel(today: today)
        case .year(let y):  return y.yearLabel(today: today)
        }
    }
}

struct PeriodTasksView: View {
    let period: TaskPeriod
    let onTaskTap: (CadenceTask) -> Void
    let onNewTask: () -> Void

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

    private var pendingCount: Int { ordered.filter { !$0.isDone }.count }
    private var doneCount: Int    { ordered.count - pendingCount }

    var body: some View {
        VStack(spacing: 0) {
            TasksHeader(title: period.titleFor(weekStartsOn: settings.weekStartsOn, today: settings.currentDate), onNewTask: onNewTask)
            Divider().background(AppTheme.headerDivider)

            if allTasks.isEmpty {
                EmptyStateView(message: "No tasks for \(period.titleFor(weekStartsOn: settings.weekStartsOn, today: settings.currentDate)).\nClick + to add one.")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if pendingCount > 0 {
                            SectionHeader(label: "To Do", count: pendingCount)
                        }

                        ForEach(ordered) { task in
                            if task.id == ordered.first(where: { $0.isDone })?.id {
                                SectionHeader(label: "Done", count: doneCount)
                                    .padding(.top, pendingCount > 0 ? 8 : 0)
                                    .transition(.opacity)
                            }

                            TaskRowView(
                                task: task,
                                onTap: { onTaskTap(task) },
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
