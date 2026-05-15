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
    /// valid Cadence backup or if its `schemaVersion` is newer than this
    /// build understands.
    ///
    /// Decoding is two-staged: a tiny `BackupHeader` is read first to check
    /// the magic marker and version. Only when those pass do we attempt the
    /// full payload decode. This means a future schema-2 backup that
    /// renames a core key will surface as `BackupError.unsupportedSchema`
    /// rather than a generic "missing key" error.
    static func decode(_ data: Data) throws -> CadenceBackup {
        let header = try decoder.decode(BackupHeader.self, from: data)
        guard header.format == CadenceBackup.formatIdentifier else {
            throw BackupError.notACadenceBackup(format: header.format)
        }
        guard header.schemaVersion <= CadenceBackup.currentSchemaVersion else {
            throw BackupError.unsupportedSchema(found: header.schemaVersion, supported: CadenceBackup.currentSchemaVersion)
        }
        return try decoder.decode(CadenceBackup.self, from: data)
    }

    /// UserDefaults key holding the most recent pre-import snapshot. Used as
    /// a manual rollback path if an import turns out to have been a mistake
    /// or was interrupted mid-write. Exposed for `restoreLastPreImport()`.
    static let preImportSnapshotKey = "cadence_pre_import_snapshot"

    /// UserDefaults flag set just before `apply` mutates anything and cleared
    /// just after. If it's still set at next launch, an import was
    /// interrupted and the user can be offered the rollback.
    static let importInProgressKey = "cadence_import_in_progress"

    /// Posted immediately before any store mutation so open editor sheets
    /// can cancel pending autosaves and dismiss themselves. Otherwise a
    /// TaskCreateView / TaskEditView left open in the main window while
    /// Settings ran the import would auto-save stale state on dismiss and
    /// silently corrupt the imported snapshot.
    static let dataWillBeReplacedNotification = Notification.Name("cadence.backup.dataWillBeReplaced")

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
        // Stash the current snapshot so a bad import can be rolled back.
        // Failure to encode here is logged but doesn't block import — the
        // user already confirmed; refusing now would be more surprising.
        if let preImportData = try? encode(makeBackup()) {
            UserDefaults.standard.set(preImportData, forKey: preImportSnapshotKey)
            // Force a write to disk so a process kill mid-import still
            // leaves the rollback snapshot recoverable on next launch.
            // `synchronize()` is officially redundant on modern macOS but
            // remains the only documented way to request an immediate flush.
            UserDefaults.standard.synchronize()
        }
        applyToStores(backup)
    }

    /// Performs the actual store mutations + interrupted-import flag
    /// bookkeeping. Split out so `restoreLastPreImport()` can replay the
    /// pre-import snapshot without clobbering the very snapshot it just
    /// read — taking a fresh `makeBackup()` of the partial/bad state at the
    /// start of a restore would destroy the only known-good rollback.
    private static func applyToStores(_ backup: CadenceBackup) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: importInProgressKey)
        defaults.synchronize()  // ensure the in-progress flag is on disk before mutating

        // Reset any in-flight pomodoro before we replace the focus map.
        // `prepareForDataReplacement` pauses (flushing any sub-second focus
        // accumulator into the about-to-be-overwritten map, which is then
        // discarded by `replaceAll`), then clears `remaining` so a later
        // Resume can't tick seconds onto the freshly imported total — the
        // imported snapshot is the source of truth from this point on.
        PomodoroTimer.shared.prepareForDataReplacement()

        // Notify any open editor sheets to abandon pending writes before we
        // overwrite their underlying store. Stale autosaves landing after
        // this point would otherwise resurrect pre-import drafts (see
        // TaskCreateView / TaskEditView onReceive handler).
        NotificationCenter.default.post(name: dataWillBeReplacedNotification, object: nil)

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

    /// True if a pre-import snapshot is available to roll back to. Drives
    /// whether the Settings UI shows the "Restore previous data" button.
    static func hasPreImportSnapshot() -> Bool {
        UserDefaults.standard.data(forKey: preImportSnapshotKey) != nil
    }

    /// Roll back to the snapshot captured just before the most recent
    /// `apply` call. Returns false if no snapshot is available (e.g. the
    /// user has never imported, or the snapshot was cleared).
    ///
    /// Restore writes directly via `applyToStores` so the existing
    /// pre-import snapshot is preserved — if the restore itself is
    /// interrupted, the user can run it again.
    @discardableResult
    static func restoreLastPreImport() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: preImportSnapshotKey),
              let snapshot = try? decode(data) else {
            return false
        }
        applyToStores(snapshot)
        return true
    }

    /// Forget the pre-import snapshot (e.g. once the user is confident the
    /// import worked and they don't want the rollback to keep showing up).
    ///
    /// Also clears the interrupted-import flag, because without a snapshot
    /// the recovery banner has nothing to offer — leaving it set would
    /// advertise a "Restore previous data" button that can only fail.
    static func clearPreImportSnapshot() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: preImportSnapshotKey)
        defaults.removeObject(forKey: importInProgressKey)
        defaults.synchronize()
    }

    /// Dismiss the interrupted-import banner without touching the rollback
    /// snapshot. Used when the user has visually confirmed the imported
    /// state looks correct but wants to keep the option to roll back.
    static func dismissInterruptedImportFlag() {
        UserDefaults.standard.removeObject(forKey: importInProgressKey)
        UserDefaults.standard.synchronize()
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
