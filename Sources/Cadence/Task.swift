import Foundation

struct Task: Identifiable {
    let id = UUID()
    var title: String
    var isDone = false
    var createdAt = Date()
}

final class TaskStore: ObservableObject {
    @Published var tasks: [Task] = []
}
