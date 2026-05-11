import Foundation

extension UUID {
    static let generalFolderID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

struct Folder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.createdAt = Date()
    }
}
