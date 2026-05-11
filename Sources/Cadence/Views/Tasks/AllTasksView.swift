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
    @Binding var selectedTask: CadenceTask?
    @Binding var showNewTask: Bool

    @State private var sortBy: AllTasksSort = .createdAt

    private var pending: [CadenceTask] {
        store.tasks.filter { !$0.isDone }.sorted(by: sortKey)
    }
    private var done: [CadenceTask] {
        store.tasks.filter { $0.isDone }.sorted(by: sortKey)
    }

    private var sortKey: (CadenceTask, CadenceTask) -> Bool {
        switch sortBy {
        case .createdAt: return { $0.createdAt < $1.createdAt }
        case .dayDeadline: return {
            ($0.dayDeadline ?? .distantFuture) < ($1.dayDeadline ?? .distantFuture)
        }
        case .weekDeadline: return {
            ($0.weekStart ?? .distantFuture) < ($1.weekStart ?? .distantFuture)
        }
        case .monthDeadline: return {
            ($0.monthStart ?? .distantFuture) < ($1.monthStart ?? .distantFuture)
        }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

                    if store.tasks.isEmpty {
                        EmptyStateView(message: "No tasks yet.\nClick + to add your first task.")
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }
}
