import Foundation
import Combine

@MainActor
final class FolderStore: ObservableObject {
    static let shared = FolderStore()

    @Published var folders: [Folder] = []
    @Published var activeFolder: Folder

    private let foldersKey       = "cadence_folders"
    private let backupKey        = "cadence_folders_backup"
    private let activeFolderIDKey = "cadence_active_folder_id"

    // False if folder data existed but couldn't be decoded.
    // Prevents a successful save from overwriting potentially-recoverable corrupt data
    // before the user explicitly modifies the folder list.
    private var dataIsReadable = true

    private init() {
        UserDefaultsMigration.ensureMigrated()

        var loaded: [Folder] = []

        if let data = UserDefaults.standard.data(forKey: "cadence_folders") {
            if let decoded = try? JSONDecoder().decode([Folder].self, from: data) {
                loaded = decoded
            } else {
                // Corrupt data — back it up and start with defaults, but mark as unreadable
                // so we don't immediately overwrite custom folder references still in TaskStore.
                UserDefaults.standard.set(data, forKey: backupKey)
                dataIsReadable = false
            }
        }

        // Always ensure the General folder exists at index 0
        if !loaded.contains(where: { $0.id == .generalFolderID }) {
            loaded.insert(Folder(id: .generalFolderID, name: "General"), at: 0)
        }

        // Recover stub folders for any folderId referenced by tasks but missing from the list.
        // This keeps tasks in custom folders reachable even after a decode failure.
        let knownIDs = Set(loaded.map { $0.id })
        for orphanID in Set(TaskStore.shared.tasks.map { $0.folderId }).subtracting(knownIDs) {
            let shortID = orphanID.uuidString.prefix(8).uppercased()
            loaded.append(Folder(id: orphanID, name: "Recovered (\(shortID))"))
        }

        folders = loaded

        // Restore previously active folder
        if let idStr = UserDefaults.standard.string(forKey: activeFolderIDKey),
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
        dataIsReadable = true  // User explicitly modified — safe to persist
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
        // Cascade-delete tasks so they don't become permanently unreachable
        TaskStore.shared.deleteAll(inFolder: folder.id)
        folders.removeAll { $0.id == folder.id }
        if activeFolder.id == folder.id {
            setActive(folders.first ?? Folder(id: .generalFolderID, name: "General"))
        }
        dataIsReadable = true
        saveFolders()
    }

    /// Replace the entire folder list (and optionally the active folder) in a
    /// single atomic step. Used by `restoreLastPreImport` so a rollback
    /// fully reverts to the pre-import snapshot, even if the user added
    /// folders afterwards.
    ///
    /// The General folder is always re-inserted at index 0 if missing so the
    /// app's invariant ("General always exists") is preserved even if the
    /// imported file is malformed.
    func replaceAll(folders newFolders: [Folder], activeFolderID: UUID?) {
        var merged = newFolders
        if !merged.contains(where: { $0.id == .generalFolderID }) {
            merged.insert(Folder(id: .generalFolderID, name: "General"), at: 0)
        }
        folders = merged
        dataIsReadable = true
        saveFolders()

        if let id = activeFolderID, let match = merged.first(where: { $0.id == id }) {
            setActive(match)
        } else {
            setActive(merged[0])
        }
    }

    /// Overlay incoming folders onto the current list. Folders present in
    /// both lists (same `id`) are updated to the incoming version (e.g. so
    /// a rename on the source device propagates). Folders only in the
    /// incoming list are appended. Local-only folders are left alone.
    ///
    /// The active folder is intentionally *not* changed — the destination
    /// device keeps its current context. Use `setActive` separately if you
    /// want the file's active to win.
    func mergeIn(folders incoming: [Folder]) {
        var incomingByID: [UUID: Folder] = [:]
        for folder in incoming { incomingByID[folder.id] = folder }

        var appliedIDs = Set<UUID>()
        for i in folders.indices {
            if let updated = incomingByID[folders[i].id] {
                folders[i] = updated
                appliedIDs.insert(updated.id)
            }
        }
        for folder in incoming where !appliedIDs.contains(folder.id) {
            folders.append(folder)
            appliedIDs.insert(folder.id)
        }

        // Defensive: preserve the "General folder always exists" invariant
        // even if both lists somehow lost it.
        if !folders.contains(where: { $0.id == .generalFolderID }) {
            folders.insert(Folder(id: .generalFolderID, name: "General"), at: 0)
        }

        dataIsReadable = true
        saveFolders()
    }

    private func saveFolders() {
        guard dataIsReadable else { return }  // Don't overwrite potentially-recoverable corrupt data
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: foldersKey)
    }
}
