import Foundation
import os

/// Phase 1 verification helper. Resolves the app's iCloud ubiquity
/// container at launch and logs the result. Used to confirm the
/// signing + entitlements are wired correctly before any sync code
/// is written in Phase 2+. Does **not** read or write any files yet.
///
/// What can go wrong here, and what the log tells us:
///
/// - `url(forUbiquityContainerIdentifier:)` returns `nil` →
///   entitlements are wrong (wrong container id, missing
///   `CloudDocuments` service, missing `app-sandbox`), or the build
///   isn't signed with a profile that includes the entitlement, or
///   the user isn't signed in to iCloud, or iCloud Drive is off.
///   Any of these would silently break sync once Phase 2 ships.
/// - A non-`nil` URL means the container exists (or was just
///   created) and lives on disk under `~/Library/Mobile Documents/`.
///   Phase 2 can start writing to its `Data/` subdirectory.
///
/// **Threading.** Apple's documentation for
/// `url(forUbiquityContainerIdentifier:)` is explicit that this call
/// can block "for a nontrivial amount of time" the first time the
/// container is materialised on a Mac, and that it must not be
/// invoked from the main thread. `run()` therefore dispatches the
/// FileManager call to a global queue and returns immediately. The
/// log emission is the entire useful side-effect for Phase 1, and
/// `Logger` is safe to use from any thread.
enum iCloudContainerProbe {
    /// Matches the value listed under
    /// `com.apple.developer.ubiquity-container-identifiers` in
    /// `Cadence.entitlements`. The strings must stay in sync — a
    /// mismatch returns `nil` with no error.
    ///
    /// The un-prefixed form (no `<TEAMID>.` prefix) is correct here:
    /// `url(forUbiquityContainerIdentifier:)` takes the exact same
    /// string that appears in the entitlement plist, and Xcode
    /// prepends the team prefix at sign time on the entitlement
    /// itself, not on this string. (Apple's documentation on this is
    /// terse but consistent with the WWDC sample code and the
    /// historical behaviour of every iCloud-using app since macOS
    /// 10.7.)
    static let containerIdentifier = "iCloud.com.orozcoding.cadence"

    private static let log = Logger(
        subsystem: "com.orozcoding.cadence",
        category: "icloud-container-probe"
    )

    /// Kicks off the probe asynchronously on a background queue and
    /// returns immediately. The result is logged via `Logger`;
    /// inspect `Console.app` with subsystem
    /// `com.orozcoding.cadence` to see the outcome.
    static func run() {
        // Identity check is cheap and runs synchronously on the
        // caller's thread — `ubiquityIdentityToken` is documented as
        // returning quickly. It gives a clearer log message before
        // the (potentially slow) container resolution begins.
        let token = FileManager.default.ubiquityIdentityToken
        if token == nil {
            log.info("No ubiquity identity token (user not signed in to iCloud, or iCloud Drive disabled). Container resolution will be nil.")
        }

        DispatchQueue.global(qos: .utility).async {
            let url = FileManager.default.url(
                forUbiquityContainerIdentifier: containerIdentifier
            )

            if let url {
                log.info("Resolved ubiquity container at \(url.path, privacy: .public)")
            } else {
                // The most common cause is entitlement / signing
                // mismatch. Surface a hint so the failure is
                // debuggable on the user's machine without needing
                // to remember the failure modes.
                log.error("""
                    Failed to resolve ubiquity container \"\(containerIdentifier, privacy: .public)\". \
                    Checklist: \
                    (1) build is signed with a profile that lists the container id; \
                    (2) Cadence.entitlements has both com.apple.developer.icloud-services=[\"CloudDocuments\"] \
                    and com.apple.developer.ubiquity-container-identifiers=[\"\(containerIdentifier, privacy: .public)\"]; \
                    (3) com.apple.security.app-sandbox is on; \
                    (4) the running user is signed in to iCloud with Drive enabled.
                    """)
            }
        }
    }
}
