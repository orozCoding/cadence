import SwiftUI

enum AllTasksSort: String, CaseIterable {
    case createdAt = "Created"
    case dayDeadline = "Day"
    case weekDeadline = "Week"
    case monthDeadline = "Month"
}

struct AllTasksView: View {
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var folderStore: FolderStore
    @Binding var selectedTask: CadenceTask?
    @Binding var showNewTask: Bool

    @State private var sortBy: AllTasksSort = .createdAt

    private var sortKey: (CadenceTask, CadenceTask) -> Bool {
        switch sortBy {
        case .createdAt:    return { $0.createdAt < $1.createdAt }
        case .dayDeadline:  return { ($0.dayDeadline ?? .distantFuture) < ($1.dayDeadline ?? .distantFuture) }
        case .weekDeadline: return { ($0.weekStart ?? .distantFuture) < ($1.weekStart ?? .distantFuture) }
        case .monthDeadline: return { ($0.monthStart ?? .distantFuture) < ($1.monthStart ?? .distantFuture) }
        }
    }

    private var ordered: [CadenceTask] {
        let fid = folderStore.activeFolder.id
        let p = store.tasks.filter { !$0.isDone && $0.folderId == fid }.sorted(by: sortKey)
        let d = store.tasks.filter {  $0.isDone && $0.folderId == fid }.sorted(by: sortKey)
        return p + d
    }

    private var folderTaskCount: Int { store.tasks.filter { $0.folderId == folderStore.activeFolder.id }.count }

    var body: some View {
        VStack(spacing: 0) {
            TasksHeader(title: "All Tasks", showNewTask: $showNewTask) {
                Picker("Sort", selection: $sortBy) {
                    ForEach(AllTasksSort.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))
            }

            Divider().background(AppTheme.divider)

            if folderTaskCount == 0 {
                EmptyStateView(message: "No tasks in \(folderStore.activeFolder.name).\nClick + to add your first task.")
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
