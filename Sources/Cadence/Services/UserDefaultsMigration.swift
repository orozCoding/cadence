import Foundation
import Darwin
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
    /// no-op. *Never* set on any access/permission error — that would
    /// turn a transient or misconfigured failure into a permanent
    /// silent fresh-install, and would close the door on future
    /// automatic recovery (e.g. if a later macOS update lifts the
    /// sandbox restriction, or the user grants additional entitlements).
    static let didMigrateKey = "cadence_did_migrate_from_unsandboxed_v1"

    /// Separate flag used only to dampen log spam when we hit a
    /// sandbox-denial path that's expected to recur every launch
    /// indefinitely. Setting this does NOT mark the migration
    /// complete — `ensureMigrated()` still re-tries the legacy read
    /// on every launch — it just downgrades subsequent denial logs
    /// from `error` to `debug` so the user's Console isn't flooded.
    /// If a denial ever turns into a success, we set `didMigrateKey`
    /// normally; this flag becomes irrelevant.
    private static let suppressedDenialLogKey = "cadence_migration_denial_logged_v1"

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

    /// Resolves the user's *real* home directory (`/Users/<user>/`),
    /// bypassing the sandbox path redirection that
    /// `FileManager.homeDirectoryForCurrentUser` is subject to.
    /// Returns `nil` only if the passwd database is genuinely
    /// unreadable after exhausting our retry budget — a pathological
    /// condition we treat as "retry on next launch".
    private static func realHomeDirectoryURL() -> URL? {
        // Start at the system's suggested size, fall back to 4096 if
        // _SC_GETPW_R_SIZE_MAX returns -1 or 0 (Darwin sometimes does).
        var bufferSize: Int = {
            let suggested = sysconf(_SC_GETPW_R_SIZE_MAX)
            return suggested > 0 ? Int(suggested) : 4096
        }()

        // Grow the buffer on ERANGE up to a sane cap. 1 MiB is far
        // larger than any realistic passwd entry; if we hit it the
        // database is corrupt and the right answer is to give up
        // and retry next launch rather than allocate unbounded.
        let maxBufferSize = 1 << 20

        while bufferSize <= maxBufferSize {
            var pw = passwd()
            var pwResult: UnsafeMutablePointer<passwd>? = nil
            var buffer = [CChar](repeating: 0, count: bufferSize)

            // `getpwuid_r` is the reentrant variant; the non-reentrant
            // `getpwuid` shares a static buffer and is unsafe across
            // threads / concurrent calls.
            let rc = getpwuid_r(getuid(), &pw, &buffer, buffer.count, &pwResult)

            if rc == 0 {
                guard pwResult != nil, let dirPtr = pw.pw_dir else {
                    // No matching entry for our uid. Pathological;
                    // give up.
                    log.error("getpwuid_r returned 0 with no matching passwd entry for uid \(getuid(), privacy: .public).")
                    return nil
                }
                return URL(fileURLWithPath: String(cString: dirPtr))
            }

            if rc == ERANGE {
                // Buffer too small — double and retry.
                bufferSize *= 2
                continue
            }

            // Any other errno: log and give up. Caller treats `nil`
            // as "leave sentinel unset, retry next launch".
            log.error("getpwuid_r failed with errno \(rc, privacy: .public) (uid \(getuid(), privacy: .public)).")
            return nil
        }

        log.error("getpwuid_r kept returning ERANGE up to \(maxBufferSize, privacy: .public)-byte buffer; giving up.")
        return nil
    }

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

        // Pristine-state check: if any known key already has a value
        // in the sandboxed defaults, the migration window has passed.
        // Either macOS's container manager auto-migrated the legacy
        // plist into the container before our code ran, *or* the user
        // has been using the app for a while (e.g. after a previous
        // launch hit sandbox-denial on the legacy read and the user
        // started accumulating new tasks/folders/focus-time anyway).
        //
        // In either case, blindly writing legacy values from a now-
        // stale plist would overwrite real data — silently. We bail
        // out and mark `didMigrateKey` so we never try again.
        //
        // Trade-off acknowledged: this re-introduces a narrow version
        // of the partial-write concern (mid-loop process kill between
        // writing key #N and setting the sentinel → next launch sees
        // partial data → pristine = false → remaining keys lost).
        // The window is microseconds of `UserDefaults.standard.set`
        // calls; this is virtually impossible in practice and is
        // an acceptable trade against silent data loss from a late
        // retry overwriting accumulated post-upgrade activity.
        let hasSandboxedData = knownKeys.contains { defaults.object(forKey: $0) != nil }
        if hasSandboxedData {
            log.info("Sandboxed defaults already populated — assuming system-level container migration handled it (or the user has been using the app). Skipping manual migration; marking done.")
            defaults.set(true, forKey: didMigrateKey)
            return
        }

        // CRITICAL: do not use `FileManager.homeDirectoryForCurrentUser`
        // here — under `com.apple.security.app-sandbox` it returns the
        // *container* path (`/Users/<user>/Library/Containers/com.orozcoding.cadence/Data/`),
        // not the real home. Asking for legacy preferences relative to
        // that path resolves to the sandboxed plist inside the
        // container, which is exactly the file we're trying to populate.
        //
        // `getpwuid_r(getuid(), …)` reads from the system passwd database
        // and is *not* subject to sandbox path redirection — it returns
        // the user's actual home directory (`/Users/<user>/`).
        guard let realHome = realHomeDirectoryURL() else {
            // Can't resolve real home — pathologically rare (would mean
            // the passwd database is unreadable). Leave sentinel unset
            // and retry next launch.
            log.error("Could not resolve real home directory via getpwuid_r; cannot locate legacy preferences. Will retry on next launch.")
            return
        }
        let legacyURL = realHome
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
            case (NSCocoaErrorDomain, NSFileReadNoPermissionError):
                // Sandbox denial: the legacy file probably exists at
                // the real path, but our entitlements don't grant us
                // access to read it. macOS's container manager should
                // have auto-migrated the preferences into the
                // sandboxed defaults during first-launch bootstrap, so
                // `UserDefaults.standard` typically already reflects
                // the user's data — our manual migration is moot in
                // the common case.
                //
                // We do **not** mark `didMigrateKey` here, because
                // doing so would close the recovery door: if both
                // auto-migration and this read failed, a future macOS
                // version that lifts the restriction (or a user
                // granting Full Disk Access / a temporary-exception
                // entitlement) could let migration succeed on a later
                // launch — but only if we keep retrying. Instead, we
                // suppress the log noise via a separate flag the next
                // time around.
                let firstTime = !defaults.bool(forKey: suppressedDenialLogKey)
                if firstTime {
                    log.notice("Sandbox denies reading legacy preferences at \(legacyURL.path, privacy: .public). Relying on macOS container manager's auto-migration; manual fallback is Settings → Data → Import. Future launches will silently retry; this notice is logged once.")
                    defaults.set(true, forKey: suppressedDenialLogKey)
                } else {
                    log.debug("Sandbox still denies reading legacy preferences at \(legacyURL.path, privacy: .public). Will retry on next launch in case macOS policy or entitlements change.")
                }
            default:
                // Other errors — `NSFileReadUnknownError`, transient
                // I/O, disk going away mid-read. Leave the sentinel
                // unset; the next launch retries.
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
