import Foundation
import os

/// Phase 1 verification helper. Resolves the app's iCloud ubiquity
/// container on launch and logs the result. Used to confirm the
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
/// This call is intentionally synchronous — Apple's docs are explicit
/// that it can block briefly the first time after entitlement changes,
/// and we want that to happen on launch (one-off, before any UI work)
/// rather than mid-write later.
@MainActor
enum iCloudContainerProbe {
    /// Matches the value listed under
    /// `com.apple.developer.ubiquity-container-identifiers` in
    /// `Cadence.entitlements`. The strings must stay in sync — a
    /// mismatch returns `nil` with no error.
    static let containerIdentifier = "iCloud.com.orozcoding.cadence"

    private static let log = Logger(
        subsystem: "com.orozcoding.cadence",
        category: "icloud-container-probe"
    )

    /// Runs the probe and logs the outcome. Returns the URL if
    /// resolution succeeded, `nil` otherwise — Phase 2+ will use the
    /// return value; for Phase 1 the side-effect (the log line) is
    /// the whole point.
    @discardableResult
    static func run() -> URL? {
        // Identity check — if the user isn't signed in to iCloud, the
        // ubiquity container resolution will also fail, but with the
        // identity check we get a clearer log message.
        let token = FileManager.default.ubiquityIdentityToken
        if token == nil {
            log.info("No ubiquity identity token (user not signed in to iCloud, or iCloud Drive disabled). Container resolution will be nil.")
        }

        let url = FileManager.default.url(
            forUbiquityContainerIdentifier: containerIdentifier
        )

        if let url {
            log.info("Resolved ubiquity container at \(url.path, privacy: .public)")
        } else {
            // The most common cause is entitlement / signing mismatch.
            // Surface a hint to make the failure debuggable on the user's
            // machine without needing to remember the failure modes.
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

        return url
    }
}
