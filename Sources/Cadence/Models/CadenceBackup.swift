import Foundation

/// A full snapshot of every persisted piece of user state: tasks, folders,
/// focus-time history, and preferences. Used to export to and import from a
/// single JSON file so the user can move state between machines.
///
/// `schemaVersion` lets us evolve the format. Newer fields should be decoded
/// with `decodeIfPresent` so older backups remain importable.
struct CadenceBackup: Codable, Equatable {
    /// The schema currently produced by this app. Bump when fields are
    /// renamed, removed, or have their semantics changed (additive fields
    /// don't require a bump as long as decoders default sensibly).
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var appVersion: String
    var exportedAt: Date

    var tasks: [CadenceTask]
    var folders: [Folder]
    var activeFolderID: UUID?
    var focusDailySeconds: [String: Int]
    var settings: BackupSettings

    init(
        schemaVersion: Int = CadenceBackup.currentSchemaVersion,
        appVersion: String,
        exportedAt: Date = Date(),
        tasks: [CadenceTask],
        folders: [Folder],
        activeFolderID: UUID?,
        focusDailySeconds: [String: Int],
        settings: BackupSettings
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.tasks = tasks
        self.folders = folders
        self.activeFolderID = activeFolderID
        self.focusDailySeconds = focusDailySeconds
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, appVersion, exportedAt
        case tasks, folders, activeFolderID, focusDailySeconds, settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        tasks = try c.decodeIfPresent([CadenceTask].self, forKey: .tasks) ?? []
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        activeFolderID = try c.decodeIfPresent(UUID.self, forKey: .activeFolderID)
        focusDailySeconds = try c.decodeIfPresent([String: Int].self, forKey: .focusDailySeconds) ?? [:]
        settings = try c.decodeIfPresent(BackupSettings.self, forKey: .settings) ?? BackupSettings()
    }
}
