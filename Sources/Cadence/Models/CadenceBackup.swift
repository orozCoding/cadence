import Foundation

/// A full snapshot of every persisted piece of user state: tasks, folders,
/// focus-time history, and preferences. Used to export to and import from a
/// single JSON file so the user can move state between machines.
///
/// `format` is a fixed magic marker that prevents an unrelated `.json` file
/// from being silently treated as a valid (empty) backup. Combined with the
/// required `schemaVersion`, it makes the import path refuse anything that
/// wasn't produced by Cadence.
struct CadenceBackup: Codable, Equatable {
    /// Magic marker written into every exported file. The decoder rejects
    /// any input that doesn't carry this exact value.
    static let formatIdentifier = "cadence-backup"

    /// The schema currently produced by this app. Bump when fields are
    /// renamed, removed, or have their semantics changed (additive fields
    /// don't require a bump as long as decoders default sensibly).
    static let currentSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var appVersion: String
    var exportedAt: Date

    var tasks: [CadenceTask]
    var folders: [Folder]
    var activeFolderID: UUID?
    var focusDailySeconds: [String: Int]
    var settings: BackupSettings

    init(
        format: String = CadenceBackup.formatIdentifier,
        schemaVersion: Int = CadenceBackup.currentSchemaVersion,
        appVersion: String,
        exportedAt: Date = Date(),
        tasks: [CadenceTask],
        folders: [Folder],
        activeFolderID: UUID?,
        focusDailySeconds: [String: Int],
        settings: BackupSettings
    ) {
        self.format = format
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
        case format, schemaVersion, appVersion, exportedAt
        case tasks, folders, activeFolderID, focusDailySeconds, settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // `format` and `schemaVersion` are required and validated up front:
        // an empty `{}` or unrelated JSON must not silently decode as an
        // empty-but-valid backup that would wipe local state on apply.
        let rawFormat = try c.decode(String.self, forKey: .format)
        guard rawFormat == CadenceBackup.formatIdentifier else {
            throw DecodingError.dataCorruptedError(
                forKey: .format,
                in: c,
                debugDescription: "Not a Cadence backup file (format = \"\(rawFormat)\")."
            )
        }
        format = rawFormat
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)

        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        tasks = try c.decodeIfPresent([CadenceTask].self, forKey: .tasks) ?? []
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        activeFolderID = try c.decodeIfPresent(UUID.self, forKey: .activeFolderID)
        focusDailySeconds = try c.decodeIfPresent([String: Int].self, forKey: .focusDailySeconds) ?? [:]
        settings = try c.decodeIfPresent(BackupSettings.self, forKey: .settings) ?? BackupSettings()
    }
}
