import SwiftUI

struct TaskListView: View {
    @StateObject private var store = TaskStore()
    @State private var newTaskTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach($store.tasks) { $task in
                    TaskRow(task: $task)
                }
                .onDelete { store.tasks.remove(atOffsets: $0) }
            }

            Divider()

            HStack {
                TextField("Add task...", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(addTask)

                Button(action: addTask) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        store.tasks.append(Task(title: title))
        newTaskTitle = ""
    }
}

struct TaskRow: View {
    @Binding var task: Task

    var body: some View {
        HStack {
            Button(action: { task.isDone.toggle() }) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .strikethrough(task.isDone, color: .secondary)
                .foregroundStyle(task.isDone ? .secondary : .primary)
        }
    }
}
