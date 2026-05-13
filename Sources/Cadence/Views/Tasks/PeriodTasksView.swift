import SwiftUI
import UniformTypeIdentifiers

struct PeriodTasksView: View {
    let period: TaskPeriod
    let onTaskTap: (CadenceTask) -> Void
    let onNewTask: () -> Void

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
            TasksHeader(title: period.titleFor(weekStartsOn: settings.weekStartsOn, today: settings.currentDate), onNewTask: onNewTask)
            Divider().background(AppTheme.divider)

            if allTasks.isEmpty {
                EmptyStateView(message: "No tasks for \(period.titleFor(weekStartsOn: settings.weekStartsOn, today: settings.currentDate)).\nClick + to add one.")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // To Do section — always rendered so it's a valid DnD target even when empty
                        SectionHeader(label: "To Do", count: todos.count)
                            .background(todoHeaderTargeted ? AppTheme.accent.opacity(0.1) : Color.clear)
                            .onDrop(of: [UTType.cadenceTaskID], isTargeted: $todoHeaderTargeted) { providers in
                                loadTaskId(providers) { id in
                                    store.setDone(id, isDone: false)
                                    // Re-read from store after mutation so the reordered list includes the moved task.
                                    let updatedTodos = allTasks.filter { !$0.isDone }
                                    store.reorder(taskIds: updatedTodos.map(\.id), periodKey: sectionKey(isDone: false))
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
                            .onDrop(of: [UTType.cadenceTaskID], isTargeted: $doneHeaderTargeted) { providers in
                                loadTaskId(providers) { id in
                                    store.setDone(id, isDone: true)
                                    // Re-read from store after mutation so the reordered list includes the moved task.
                                    let updatedDones = allTasks.filter { $0.isDone }
                                    store.reorder(taskIds: updatedDones.map(\.id), periodKey: sectionKey(isDone: true))
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
                // Clear stale drag state when the dragged task leaves or is modified by a sidebar drop.
                // "Same-period" sidebar drops keep the task in allTasks but mutate it (periodSortKeys),
                // so we also clear when the task's content changed while draggedId is still set.
                .onChange(of: allTasks) { oldTasks, newTasks in
                    guard let did = draggedId else { return }
                    let stillPresent = newTasks.contains(where: { $0.id == did })
                    let wasModified = oldTasks.first(where: { $0.id == did }) != newTasks.first(where: { $0.id == did })
                    if !stillPresent || wasModified {
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
                onTap: { onTaskTap(task) },
                onToggle: {
                    let willBeDone = !task.isDone
                    store.toggle(task)
                    let destKey = sectionKey(isDone: willBeDone)
                    // Re-read from store after mutation to include the toggled task in the reorder.
                    let destIds = allTasks.filter { willBeDone ? $0.isDone : !$0.isDone }.map(\.id)
                    store.reorder(taskIds: destIds, periodKey: destKey)
                }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .opacity(draggedId == task.id ? 0.4 : 1.0)
            .onDrag {
                draggedId = task.id
                let provider = NSItemProvider()
                let uuidData = task.id.uuidString.data(using: .utf8) ?? Data()
                provider.registerDataRepresentation(for: .cadenceTaskID, visibility: .all) { completion in
                    completion(uuidData, nil)
                    return nil
                }
                return provider
            }
            .onDrop(
                of: [UTType.cadenceTaskID],
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
            .accessibilityAction(named: "Move Up") {
                guard let idx = tasks.firstIndex(where: { $0.id == task.id }), idx > 0 else { return }
                var ids = tasks.map(\.id)
                ids.swapAt(idx, idx - 1)
                store.reorder(taskIds: ids, periodKey: key)
            }
            .accessibilityAction(named: "Move Down") {
                guard let idx = tasks.firstIndex(where: { $0.id == task.id }), idx < tasks.count - 1 else { return }
                var ids = tasks.map(\.id)
                ids.swapAt(idx, idx + 1)
                store.reorder(taskIds: ids, periodKey: key)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))

            if dropTargetId == task.id && !dropAbove {
                DragInsertionLine().padding(.horizontal, 20)
            }
        }
    }

    private func loadTaskId(_ providers: [NSItemProvider], action: @escaping (UUID) -> Void) {
        _ = providers.first?.loadDataRepresentation(for: .cadenceTaskID) { data, _ in
            guard let data, let str = String(data: data, encoding: .utf8), let id = UUID(uuidString: str) else { return }
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
