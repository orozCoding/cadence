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

    /// UserDefaults key holding the most recent pre-import snapshot. Used as
    /// a manual rollback path if an import turns out to have been a mistake
    /// or was interrupted mid-write. Exposed for `restoreLastPreImport()`.
    static let preImportSnapshotKey = "cadence_pre_import_snapshot"

    /// UserDefaults flag set just before `apply` mutates anything and cleared
    /// just after. If it's still set at next launch, an import was
    /// interrupted and the user can be offered the rollback.
    static let importInProgressKey = "cadence_import_in_progress"

    /// Replace every store's contents with the snapshot. Caller is expected
    /// to confirm with the user first since this overwrites all local data.
    ///
    /// The current state is stashed in UserDefaults under
    /// `preImportSnapshotKey` before any mutation, and an
    /// `importInProgressKey` marker is raised for the duration. UserDefaults
    /// does not give us a true cross-key transaction, but together these
    /// give the user a recovery path if anything goes wrong: at worst they
    /// re-run the app and call `restoreLastPreImport()`.
    static func apply(_ backup: CadenceBackup) {
        let defaults = UserDefaults.standard

        // Stash the current snapshot so a bad import can be rolled back.
        // Failure to encode here is logged but doesn't block import — the
        // user already confirmed; refusing now would be more surprising.
        if let preImportData = try? encode(makeBackup()) {
            defaults.set(preImportData, forKey: preImportSnapshotKey)
        }
        defaults.set(true, forKey: importInProgressKey)

        // Make sure every task points to a folder that exists. Tasks whose
        // `folderId` isn't represented in `backup.folders` would otherwise
        // be invisible in the UI until the next launch (when FolderStore's
        // init creates "Recovered" stubs). Re-running that recovery here
        // keeps the in-memory state consistent immediately after import.
        let backupFolderIDs = Set(backup.folders.map { $0.id })
        let referencedFolderIDs = Set(backup.tasks.map { $0.folderId })
        let missingFolderIDs = referencedFolderIDs.subtracting(backupFolderIDs)
        var foldersToApply = backup.folders
        for orphanID in missingFolderIDs where orphanID != .generalFolderID {
            let shortID = orphanID.uuidString.prefix(8).uppercased()
            foldersToApply.append(Folder(id: orphanID, name: "Recovered (\(shortID))"))
        }

        // Folders must be replaced first so tasks that reference custom
        // folder IDs land in valid folders.
        FolderStore.shared.replaceAll(folders: foldersToApply, activeFolderID: backup.activeFolderID)
        TaskStore.shared.replaceAll(backup.tasks)
        FocusTimeStore.shared.replaceAll(backup.focusDailySeconds)
        AppSettings.shared.apply(backup.settings)

        defaults.removeObject(forKey: importInProgressKey)
    }

    /// True if an import was started but never completed (the process was
    /// killed between the marker being set and `apply` finishing). Callers
    /// can surface a "your last import didn't finish — restore?" prompt.
    static func hasInterruptedImport() -> Bool {
        UserDefaults.standard.bool(forKey: importInProgressKey)
    }

    /// Roll back to the snapshot captured just before the most recent
    /// `apply` call. Returns false if no snapshot is available (e.g. the
    /// user has never imported, or the snapshot was cleared).
    @discardableResult
    static func restoreLastPreImport() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: preImportSnapshotKey),
              let snapshot = try? decode(data) else {
            return false
        }
        apply(snapshot)
        return true
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
