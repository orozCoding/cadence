import SwiftUI
import UniformTypeIdentifiers

struct PeriodTasksView: View {
    let period: TaskPeriod
    @Binding var selectedTask: CadenceTask?
    @Binding var showNewTask: Bool

    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var folderStore: FolderStore

    @State private var draggedId: UUID? = nil
    @State private var dropTargetId: UUID? = nil
    @State private var dropAbove: Bool = true
    @State private var todoHeaderTargeted = false
    @State private var doneHeaderTargeted = false

    private var allTasks: [CadenceTask] {
        let fid = folderStore.activeFolder.id
        switch period {
        case .day(let d):   return store.tasks(forDay: d, folderId: fid)
        case .week(let s):  return store.tasks(forWeek: s, weekStartsOn: settings.weekStartsOn, folderId: fid)
        case .month(let s): return store.tasks(forMonth: s, folderId: fid)
        case .year(let y):  return store.tasks(forYear: y, folderId: fid)
        }
    }

    private var todos: [CadenceTask] { allTasks.filter { !$0.isDone } }
    private var dones: [CadenceTask] { allTasks.filter { $0.isDone } }

    // Section-scoped sort keys prevent index collisions between To-Do and Done.
    private func sectionKey(isDone: Bool) -> String {
        (isDone ? "dn:" : "td:") + period.storageKey
    }

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
                        // To Do section — always rendered so it's a valid DnD target even when empty
                        SectionHeader(label: "To Do", count: todos.count)
                            .background(todoHeaderTargeted ? AppTheme.accent.opacity(0.1) : Color.clear)
                            .onDrop(of: [UTType.plainText], isTargeted: $todoHeaderTargeted) { providers in
                                loadTaskId(providers) { id in
                                    store.setDone(id, isDone: false)
                                    draggedId = nil
                                    dropTargetId = nil
                                }
                                return true
                            }
                        periodTaskRows(tasks: todos, isDoneSection: false)

                        // Done section — always rendered so it's a valid DnD target even when empty
                        SectionHeader(label: "Done", count: dones.count)
                            .padding(.top, 8)
                            .background(doneHeaderTargeted ? AppTheme.accent.opacity(0.1) : Color.clear)
                            .transition(.opacity)
                            .onDrop(of: [UTType.plainText], isTargeted: $doneHeaderTargeted) { providers in
                                loadTaskId(providers) { id in
                                    store.setDone(id, isDone: true)
                                    draggedId = nil
                                    dropTargetId = nil
                                }
                                return true
                            }
                        periodTaskRows(tasks: dones, isDoneSection: true)
                    }
                    .padding(.vertical, 12)
                    .animation(.easeInOut(duration: 0.28), value: allTasks)
                }
                // When the dragged task leaves this period view (e.g. via a sidebar drop),
                // clear stale drag state so no ghost highlight remains.
                .onChange(of: allTasks) { _, newTasks in
                    if let did = draggedId, !newTasks.contains(where: { $0.id == did }) {
                        draggedId = nil
                        dropTargetId = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func periodTaskRows(tasks: [CadenceTask], isDoneSection: Bool) -> some View {
        let key = sectionKey(isDone: isDoneSection)
        ForEach(tasks) { task in
            if dropTargetId == task.id && dropAbove {
                DragInsertionLine().padding(.horizontal, 20)
            }

            TaskRowView(
                task: task,
                onTap: { withAnimation { selectedTask = task } },
                onToggle: { store.toggle(task) }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .opacity(draggedId == task.id ? 0.4 : 1.0)
            .onDrag {
                draggedId = task.id
                return NSItemProvider(object: task.id.uuidString as NSString)
            }
            .onDrop(
                of: [UTType.plainText],
                delegate: TaskReorderDelegate(
                    targetTask: task,
                    sectionTasks: tasks,
                    sectionKey: key,
                    draggedId: $draggedId,
                    dropTargetId: $dropTargetId,
                    dropAbove: $dropAbove,
                    store: store
                )
            )
            .transition(.opacity.combined(with: .move(edge: .top)))

            if dropTargetId == task.id && !dropAbove {
                DragInsertionLine().padding(.horizontal, 20)
            }
        }
    }

    private func loadTaskId(_ providers: [NSItemProvider], action: @escaping (UUID) -> Void) {
        providers.first?.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            guard let str = item as? String, let id = UUID(uuidString: str) else { return }
            DispatchQueue.main.async { action(id) }
        }
    }
}

// MARK: - Drop Delegate

private struct TaskReorderDelegate: DropDelegate {
    let targetTask: CadenceTask
    let sectionTasks: [CadenceTask]
    let sectionKey: String  // "td:<periodKey>" or "dn:<periodKey>"
    @Binding var draggedId: UUID?
    @Binding var dropTargetId: UUID?
    @Binding var dropAbove: Bool
    let store: TaskStore

    func dropEntered(info: DropInfo) {
        guard draggedId != nil, draggedId != targetTask.id else { return }
        dropTargetId = targetTask.id
        dropAbove = info.location.y < AppTheme.rowHeight / 2
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedId != nil, draggedId != targetTask.id else {
            return DropProposal(operation: .forbidden)
        }
        dropAbove = info.location.y < AppTheme.rowHeight / 2
        dropTargetId = targetTask.id
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTargetId == targetTask.id { dropTargetId = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedId = nil
            dropTargetId = nil
        }
        guard let fromId = draggedId, fromId != targetTask.id else { return false }

        let above = dropAbove

        if sectionTasks.contains(where: { $0.id == fromId }) {
            // Same section: reorder preserving section-specific sort key
            var ids = sectionTasks.map(\.id)
            ids.removeAll { $0 == fromId }
            let toIdx = ids.firstIndex(of: targetTask.id) ?? ids.count
            ids.insert(fromId, at: above ? toIdx : min(toIdx + 1, ids.count))
            store.reorder(taskIds: ids, periodKey: sectionKey)
        } else {
            // Cross-section: toggle done status, then place near target in the destination section
            store.setDone(fromId, isDone: targetTask.isDone)
            var ids = sectionTasks.map(\.id)
            let toIdx = ids.firstIndex(of: targetTask.id) ?? ids.count
            ids.insert(fromId, at: above ? toIdx : min(toIdx + 1, ids.count))
            store.reorder(taskIds: ids, periodKey: sectionKey)
        }
        return true
    }
}

// MARK: - Insertion Line

private struct DragInsertionLine: View {
    var body: some View {
        Capsule()
            .fill(AppTheme.accent)
            .frame(height: 2)
    }
}
