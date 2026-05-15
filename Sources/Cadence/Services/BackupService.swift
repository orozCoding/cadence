import Foundation

/// Builds and applies `CadenceBackup` snapshots. Glue between the file
/// (Codable JSON) and the live stores. Pure logic — no UI here so this layer
/// stays testable and reusable from anywhere on the main actor.
@MainActor
enum BackupService {
    /// JSON encoder used for export. Pretty-printed and key-sorted so the
    /// resulting file is human-readable and produces stable diffs.
    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Build a snapshot containing every piece of user state currently in
    /// memory. Calls `flushIfNeeded` on the focus store first so any
    /// in-flight focus seconds from a running timer are included.
    static func makeBackup() -> CadenceBackup {
        FocusTimeStore.shared.flushIfNeeded()
        return CadenceBackup(
            appVersion: appVersionString(),
            tasks: TaskStore.shared.tasks,
            folders: FolderStore.shared.folders,
            activeFolderID: FolderStore.shared.activeFolder.id,
            focusDailySeconds: FocusTimeStore.shared.dailySeconds,
            settings: AppSettings.shared.snapshot()
        )
    }

    /// Encode a snapshot to JSON bytes ready to be written to disk.
    static func encode(_ backup: CadenceBackup) throws -> Data {
        try encoder.encode(backup)
    }

    /// Decode JSON bytes back into a snapshot. Throws if the file is not a
    /// valid Cadence backup.
    static func decode(_ data: Data) throws -> CadenceBackup {
        try decoder.decode(CadenceBackup.self, from: data)
    }

    /// Replace every store's contents with the snapshot. Caller is expected
    /// to confirm with the user first since this overwrites all local data.
    static func apply(_ backup: CadenceBackup) {
        // Folders must be replaced first so tasks that reference custom
        // folder IDs land in valid folders. TaskStore tolerates unknown
        // folder IDs (FolderStore creates "Recovered" stubs at next launch),
        // but ordering it this way avoids that fallback in the happy path.
        FolderStore.shared.replaceAll(folders: backup.folders, activeFolderID: backup.activeFolderID)
        TaskStore.shared.replaceAll(backup.tasks)
        FocusTimeStore.shared.replaceAll(backup.focusDailySeconds)
        AppSettings.shared.apply(backup.settings)
    }

    /// Suggested filename for a fresh export, e.g. `cadence-backup-2026-05-15.json`.
    static func suggestedFilename(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return "cadence-backup-\(f.string(from: now)).json"
    }

    private static func appVersionString() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}
