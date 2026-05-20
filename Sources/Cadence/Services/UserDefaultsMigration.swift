import Foundation
import os

/// One-shot migration that copies preferences from the pre-sandbox
/// `~/Library/Preferences/com.orozcoding.cadence.plist` into the new
/// sandboxed UserDefaults domain
/// (`~/Library/Containers/com.orozcoding.cadence/Data/Library/Preferences/com.orozcoding.cadence.plist`).
///
/// Why this exists: enabling `com.apple.security.app-sandbox` in
/// `Cadence.entitlements` re-roots the app's preferences domain. Without
/// this shim, a user upgrading from an un-sandboxed build would launch the
/// new build to an empty state (no tasks, no folders, no focus history, no
/// settings) — every UserDefaults key the existing app uses is in the
/// legacy file the sandbox no longer sees.
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
    /// Set after a successful migration so subsequent launches no-op.
    /// Stored in the sandboxed defaults — i.e., after migration we can
    /// see the flag and skip; if a user later moves to a different Mac
    /// without iCloud sync set up yet, the flag is absent there and the
    /// migration re-runs reading from that Mac's own legacy plist.
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
    ///   `timerDirection`, `animateDockIcon`
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

    /// Runs the migration if it hasn't run yet. Idempotent: safe to call
    /// multiple times. After the first run sets `didMigrateKey`,
    /// subsequent calls return immediately after a single bool read.
    static func ensureMigrated() {
        let defaults = UserDefaults.standard

        // Already migrated on this Mac — nothing to do. The legacy file
        // may still be on disk (we intentionally don't delete it; if the
        // user reverts to an older un-sandboxed build they keep their
        // data) but we don't re-copy on every launch.
        if defaults.bool(forKey: didMigrateKey) {
            return
        }

        // If the sandboxed domain already has any of the known keys, the
        // user has been running the sandboxed build for at least one
        // session, presumably stored their own data, and we shouldn't
        // overwrite it. Mark migrated and exit.
        let hasSandboxedData = knownKeys.contains { defaults.object(forKey: $0) != nil }
        if hasSandboxedData {
            log.info("Sandboxed defaults already populated; marking migration done without copying.")
            defaults.set(true, forKey: didMigrateKey)
            return
        }

        // Locate the pre-sandbox preferences plist. Hard-coded path
        // because the sandbox prevents us from asking `CFPreferences`
        // for the un-sandboxed copy — we have to read the file ourselves.
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let legacyURL = homeURL
            .appendingPathComponent("Library/Preferences/\(legacyBundleID).plist")

        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            log.info("No legacy preferences file at \(legacyURL.path, privacy: .public); fresh sandboxed install, nothing to migrate.")
            defaults.set(true, forKey: didMigrateKey)
            return
        }

        // Read the plist. PropertyListSerialization handles both XML and
        // binary plist formats, which CFPreferences uses interchangeably.
        guard let data = try? Data(contentsOf: legacyURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any] else {
            log.error("Failed to read or parse legacy preferences at \(legacyURL.path, privacy: .public); marking migration done to avoid retry loop.")
            defaults.set(true, forKey: didMigrateKey)
            return
        }

        // Copy each known key. We do NOT copy unknown keys because:
        //   (a) System adds noise like `NSWindow Frame …` that we don't want,
        //   (b) accidentally importing a stale key is worse than missing it.
        var migrated = 0
        for key in knownKeys {
            guard let value = plist[key] else { continue }
            defaults.set(value, forKey: key)
            migrated += 1
        }

        log.info("Migrated \(migrated, privacy: .public) UserDefaults keys from legacy domain into sandboxed container.")
        defaults.set(true, forKey: didMigrateKey)
    }
}
