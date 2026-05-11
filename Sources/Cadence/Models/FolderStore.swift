import Foundation
import Combine

@MainActor
final class FolderStore: ObservableObject {
    static let shared = FolderStore()

    @Published var folders: [Folder] = []
    @Published var activeFolder: Folder

    private let foldersKey = "cadence_folders"
    private let activeFolderIDKey = "cadence_active_folder_id"

    private init() {
        var loaded: [Folder] = []
        if let data = UserDefaults.standard.data(forKey: "cadence_folders"),
           let decoded = try? JSONDecoder().decode([Folder].self, from: data) {
            loaded = decoded
        }

        // Always ensure the General folder exists at index 0
        if !loaded.contains(where: { $0.id == .generalFolderID }) {
            loaded.insert(Folder(id: .generalFolderID, name: "General"), at: 0)
        }
        folders = loaded

        // Restore previously active folder
        if let idStr = UserDefaults.standard.string(forKey: "cadence_active_folder_id"),
           let uuid = UUID(uuidString: idStr),
           let match = loaded.first(where: { $0.id == uuid }) {
            activeFolder = match
        } else {
            activeFolder = loaded[0]
        }
    }

    func add(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let folder = Folder(name: trimmed)
        folders.append(folder)
        saveFolders()
        setActive(folder)
    }

    func setActive(_ folder: Folder) {
        guard let found = folders.first(where: { $0.id == folder.id }) else { return }
        activeFolder = found
        UserDefaults.standard.set(found.id.uuidString, forKey: activeFolderIDKey)
    }

    func delete(_ folder: Folder) {
        guard folder.id != .generalFolderID else { return }
        folders.removeAll { $0.id == folder.id }
        if activeFolder.id == folder.id {
            setActive(folders.first ?? Folder(id: .generalFolderID, name: "General"))
        }
        saveFolders()
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: foldersKey)
    }
}
