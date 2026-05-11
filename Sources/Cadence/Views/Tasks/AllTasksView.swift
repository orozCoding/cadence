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
    private var pendingCount: Int    { ordered.filter { !$0.isDone }.count }
    private var doneCount: Int       { ordered.count - pendingCount }

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
