import SwiftUI

/// Renders a sorted task list with "To Do" / "Done" section headers.
/// Caller is responsible for ordering: pending tasks first, completed tasks last.
struct TaskListView: View {
    let tasks: [CadenceTask]
    let onTap: (CadenceTask) -> Void
    let onToggle: (CadenceTask) -> Void

    private var pendingCount: Int { tasks.filter { !$0.isDone }.count }
    private var doneCount: Int    { tasks.count - pendingCount }

    var body: some View {
        let firstDoneId = tasks.first(where: { $0.isDone })?.id
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if pendingCount > 0 {
                    SectionHeader(label: "To Do", count: pendingCount)
                }

                ForEach(tasks) { task in
                    if task.id == firstDoneId {
                        SectionHeader(label: "Done", count: doneCount)
                            .padding(.top, pendingCount > 0 ? 8 : 0)
                            .transition(.opacity)
                    }

                    TaskRowView(
                        task: task,
                        onTap: { onTap(task) },
                        onToggle: { onToggle(task) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 12)
            .animation(.easeInOut(duration: 0.28), value: tasks.map(\.id))
        }
    }
}
