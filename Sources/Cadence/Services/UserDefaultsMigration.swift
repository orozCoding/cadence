import Foundation
import os

/// One-shot migration that copies preferences from the pre-sandbox
/// `~/Library/Preferences/com.orozcoding.cadence.plist` into the new
/// sandboxed UserDefaults domain
/// (`~/Library/Containers/com.orozcoding.cadence/Data/Library/Preferences/com.orozcoding.cadence.plist`).
///
/// Why this exists: enabling `com.apple.security.app-sandbox` in
/// `Cadence.entitlements` re-roots the app's preferences domain. macOS's
/// container manager *usually* auto-migrates `~/Library/Preferences/<id>.plist`
/// into the new container on first sandboxed launch, but the behaviour is
/// not 100% reliable across macOS versions / cfprefsd cache states. This
/// shim is belt-and-braces: if the system migration worked we're a no-op,
/// and if it didn't we recover the user's data ourselves.
///
/// `ensureMigrated()` must be invoked **before** any code that reads
/// UserDefaults — in particular before the `AppSettings.shared`,
/// `TaskStore.shared`, `FolderStore.shared`, and `FocusTimeStore.shared`
/// singletons read their stored keys. Because SwiftUI evaluates the
/// `@StateObject` field initialisers in `CadenceApp.init()` *before*
/// `applicationDidFinishLaunching` runs, hooking this from the app
/// delegate alone is too late.
///
/// The chosen pattern: every store calls `ensureMigrated()` at the top
/// of its `init` body, before any `UserDefaults.standard.*` read. The
/// call is idempotent — after the first run sets `didMigrateKey`,
/// subsequent calls are an O(1) bool read and return immediately.
/// Whichever store SwiftUI happens to initialise first runs the
/// migration; the others see the already-migrated state.
@MainActor
enum UserDefaultsMigration {
    /// Set after a confirmed-complete migration so subsequent launches
    /// no-op. *Never* set on an access/permission error — that would
    /// turn a transient or misconfigured failure into a permanent
    /// silent fresh-install.
    static let didMigrateKey = "cadence_did_migrate_from_unsandboxed_v1"

    /// Bundle id used to locate the legacy preferences file. Hard-coded
    /// rather than read from `Bundle.main.bundleIdentifier` so a future
    /// rename of the bundle id doesn't silently miss the migration.
    private static let legacyBundleID = "com.orozcoding.cadence"

    /// Every UserDefaults key the existing un-sandboxed app writes. If
    /// any new key is added in `AppSettings` / a Store, add it here too,
    /// otherwise that one preference will silently reset on the
    /// first-ever sandboxed launch.
    ///
    /// Sources of truth (greppable strings in the codebase):
    /// - AppSettings.swift: `weekStartsOn`, `timerFinishSound`, `timerStyle`,
    ///   `timerDirection`, `animateDockIcon`, `iCloudSyncEnabled`
    /// - TaskStore.swift: `cadence_tasks`, `cadence_tasks_backup`
    /// - FolderStore.swift: `cadence_folders`, `cadence_folders_backup`,
    ///   `cadence_active_folder_id`
    /// - FocusTimeStore.swift: `focusDailySeconds`, `focusDailySeconds_backup`
    /// - BackupService.swift: `cadence_pre_import_snapshot`,
    ///   `cadence_import_in_progress`
    private static let knownKeys: [String] = [
        // AppSettings
        "weekStartsOn", "timerFinishSound", "timerStyle", "timerDirection",
        "animateDockIcon", "iCloudSyncEnabled",
        // TaskStore
        "cadence_tasks", "cadence_tasks_backup",
        // FolderStore
        "cadence_folders", "cadence_folders_backup", "cadence_active_folder_id",
        // FocusTimeStore
        "focusDailySeconds", "focusDailySeconds_backup",
        // BackupService
        "cadence_pre_import_snapshot", "cadence_import_in_progress"
    ]

    private static let log = Logger(subsystem: legacyBundleID, category: "userdefaults-migration")

    /// Runs the migration if it hasn't run yet. Idempotent: safe to
    /// call multiple times. After the first run sets `didMigrateKey`,
    /// subsequent calls return immediately after a single bool read.
    ///
    /// Atomicity / partial-state safety: we read every key into memory
    /// *first*, then write the batch to UserDefaults, then set the
    /// sentinel last. If the process is killed at any point before the
    /// sentinel is set, the next launch re-runs the whole migration
    /// from scratch — the sandboxed defaults are still in a consistent
    /// state because writes are idempotent (writing the same value
    /// twice is fine) and we haven't lied about completion. There is
    /// no resumable mid-migration state to confuse on retry.
    static func ensureMigrated() {
        let defaults = UserDefaults.standard

        if defaults.bool(forKey: didMigrateKey) {
            // Already done. The legacy file may still be on disk (we
            // intentionally don't delete it; if the user reverts to an
            // older un-sandboxed build they keep their data) but we
            // don't re-copy on every launch.
            return
        }

        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let legacyURL = homeURL
            .appendingPathComponent("Library/Preferences/\(legacyBundleID).plist")

        // We deliberately do NOT pre-check with
        // `FileManager.fileExists(atPath:)`: it returns `false` for both
        // "file is genuinely absent" and "file exists but the sandbox
        // denies us access", which conflates two situations that need
        // different responses. Letting `Data(contentsOf:)` throw and
        // then inspecting the NSError code distinguishes them.
        let data: Data
        do {
            data = try Data(contentsOf: legacyURL)
        } catch let error as NSError {
            switch (error.domain, error.code) {
            case (NSCocoaErrorDomain, NSFileReadNoSuchFileError):
                // Genuinely no legacy file. Either a true fresh install,
                // or the system's container manager already auto-migrated
                // the preferences plist into the sandbox container as
                // part of first-launch bootstrap — both equivalent from
                // our perspective (the live `UserDefaults.standard`
                // reflects the right state either way). Safe to set the
                // sentinel.
                log.info("No legacy preferences file at \(legacyURL.path, privacy: .public); fresh install or system-level container migration already handled. Marking migration done.")
                defaults.set(true, forKey: didMigrateKey)
            default:
                // Anything else — `NSFileReadNoPermissionError` (sandbox
                // denial), `NSFileReadUnknownError`, transient I/O — we
                // don't know whether legacy data exists. Leave the
                // sentinel unset; the next launch retries. Harmless:
                // one log line, no UserDefaults writes. Far better than
                // marking done and losing the migration window forever.
                // If the failure is permanent (e.g. sandbox policy
                // blocking us on this macOS version), the recovery is
                // the existing Settings → Data → Import flow from a
                // backup of the un-sandboxed build.
                log.error("Could not read legacy preferences at \(legacyURL.path, privacy: .public): \(error, privacy: .public) (code \(error.code, privacy: .public)). Will retry on next launch.")
            }
            return
        }

        // Case 3: file read succeeded. Try to parse.
        let plist: [String: Any]
        do {
            let parsed = try PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            )
            guard let dict = parsed as? [String: Any] else {
                log.error("Legacy preferences plist at \(legacyURL.path, privacy: .public) is not a top-level dictionary; marking migration done — there's nothing recoverable.")
                defaults.set(true, forKey: didMigrateKey)
                return
            }
            plist = dict
        } catch {
            // Corrupt plist. Mark done — retrying every launch would
            // just log the same error forever, and there's nothing
            // we can recover from an unparseable file.
            log.error("Legacy preferences plist at \(legacyURL.path, privacy: .public) failed to parse: \(error, privacy: .public). Marking migration done.")
            defaults.set(true, forKey: didMigrateKey)
            return
        }

        // Case 4: success path. Collect all values, write in one batch,
        // then set the sentinel. If killed mid-batch the next launch
        // re-runs from scratch (the sentinel is the only completion
        // gate); writes are idempotent so no harm done.
        //
        // We do NOT copy unknown keys because:
        //   (a) System / framework noise like `NSWindow Frame …` is
        //       irrelevant and would just clutter the sandboxed plist,
        //   (b) accidentally importing a stale key is worse than
        //       missing it.
        let migratedPairs: [(String, Any)] = knownKeys.compactMap { key in
            plist[key].map { (key, $0) }
        }

        for (key, value) in migratedPairs {
            defaults.set(value, forKey: key)
        }

        log.info("Migrated \(migratedPairs.count, privacy: .public) UserDefaults keys from legacy domain into sandboxed container.")
        defaults.set(true, forKey: didMigrateKey)
    }
}
