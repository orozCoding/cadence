# Multi-Mac Sync — Planning Document

This is a **research / planning PR**. No production code is changed. The goal
is to agree on an approach before any sync code lands.

## What the user asked for

> "Be able to switch between my MacBooks and have my info sync up, without
> the app needing to be online 100% of the time. It can operate even if I
> lose internet for hours. We can already sync manually if I'm right — I
> want no effort after some setup."

Translated into requirements:

- **Offline-first.** Editing tasks, running the Pomodoro, completing
  checklist items must work with the network unplugged, indefinitely.
- **Background sync.** When connectivity returns, changes flow both ways
  automatically. No "Sync now" button to remember.
- **Setup is one-time.** Sign in once per Mac (or pick a folder once), then
  it's invisible.
- **Personal scope.** One user, two (or N) of their own Macs. No team
  sharing, no auth UI to build.

## What we already have (and why this is small)

`dev` ships a full backup pipeline (`a6a81b3` … `d8ad3d8`):

- `CadenceBackup` — a Codable snapshot of *every* user-facing piece of
  state: tasks, folders, active folder, daily focus seconds, settings.
  Versioned via `formatIdentifier` + `schemaVersion`.
- `BackupService.makeBackup() / encode / decode / apply` — pure logic,
  no UI.
- `BackupService.apply()` uses **merge** semantics already designed for
  cross-machine use: same-`id` tasks/folders are overwritten by the incoming
  copy; focus-day keys are overwritten per day; settings are taken
  wholesale; local-only records are preserved. There's a pre-import
  snapshot for rollback and an interrupted-import marker for crash
  recovery.
  - ⚠️ **Known limitation for continuous sync:** "settings taken wholesale"
    is fine for a one-shot import but is a silent conflict sink when sync
    runs on every change. If Mac A changes the theme and Mac B (with the
    old theme still in its snapshot) writes later, Mac B's snapshot will
    silently revert Mac A's theme change. Acceptable for personal use with
    light settings churn, but **must be called out explicitly**, and a
    follow-on task can add per-key, timestamped settings merge if it bites
    in practice.
- The stores (`TaskStore`, `FolderStore`, `FocusTimeStore`, `AppSettings`)
  expose `mergeIn` and `replaceAll`.

The expensive parts — the format, the conflict policy, the rollback path —
are done. What's missing is **a transport that does the export/import on a
schedule, automatically, both ways.**

That framing keeps each of the three options below to "wire a transport
behind the existing `BackupService`" rather than "redesign sync."

---

## Three options

### Option 1 — iCloud Drive ubiquity container (FAVORITE) ⭐

**Shape.** The app writes the same `CadenceBackup` JSON we already produce
into a single file inside the app's iCloud ubiquity container
(`~/Library/Mobile Documents/iCloud~com~orozcoding~cadence/Documents/cadence-state.json`).
macOS syncs that file across Macs signed into the same Apple ID for free.

**Read path.** On launch and whenever `NSMetadataQuery` (scoped to
`NSMetadataQueryUbiquitousDocumentsScope`, observing
`NSMetadataQueryDidUpdateNotification`) reports the ubiquitous file
changed, we:

1. Inspect `NSMetadataUbiquitousItemDownloadingStatusKey` on the updated
   item. If it is not `NSMetadataUbiquitousItemDownloadingStatusCurrent`,
   call `FileManager.default.startDownloadingUbiquitousItem(at:)` and wait
   for the next metadata update that signals `.current` before reading.
2. Open a coordinated read, `BackupService.decode` the file, and call
   `BackupService.apply()` — the existing merge code does the rest.

`NSFilePresenter` is **not** an alternative here: the iCloud daemon (`bird`)
does not coordinate writes on our behalf when it pulls a new version from
the cloud, so a presenter would silently miss remote updates.
`NSMetadataQuery` is the only correct mechanism for detecting remote
changes. Skipping the download-status check is a hang/data-loss risk
whenever the Mac is low on disk and iCloud has evicted the file under
"Optimise Mac Storage".

**Write path.** Any mutating call on a store flips a "dirty" flag. A
debounced writer takes a fresh `makeBackup()`, encodes it, and writes
the file under `NSFileCoordinator` so iCloud sees an atomic update.
Hard constraints:

- The coordinated write **must run off the main thread** (`NSFileCoordinator`
  blocks; doing this on main freezes the UI under sync contention).
- Two debounce knobs, both required: a short **idle debounce** (~5 s) so
  rapid typing bursts collapse into one write, and a **max-dirty-age
  ceiling** (~30 s) so a user who types continuously still gets their
  edits flushed.
- `applicationWillResignActive` and `applicationWillTerminate` flush
  immediately as a safety net — not the primary cadence.
- `makeBackup()` snapshots the entire state graph; for a power user
  this is non-trivial JSON. Encoding belongs on a background queue too.

**Offline behaviour.** iCloud Drive is offline-first by design: the file
sits on local disk, edits write through immediately, the daemon uploads
when reachable. If both Macs edit while offline, iCloud surfaces a
conflict file we resolve with the same `mergeIn` logic (last-writer-wins
per record, never destructive to local-only records).

**Setup.** One toggle in Settings → "Sync via iCloud". Both Macs need to be
signed into the same iCloud account (they already are, for any
single-user macOS setup).

**Pros**

- **Reuses 100% of the existing backup pipeline.** The transport is the
  only new code; merge, validation, rollback, schema versioning are done.
- **Truly zero infra.** No server, no auth, no costs at any scale.
- **Offline-first is the *default* behaviour**, not something we have to
  engineer.
- **Conflict copies are rare in practice** because this is a single-user
  app and concurrent offline editing across two of the same person's Macs
  is uncommon. (To be clear: `NSFileCoordinator` only coordinates writes
  between processes on the *same* Mac — it does **not** prevent two
  different Macs from writing simultaneously to the same ubiquitous file.
  Cross-Mac divergence is detected later by iCloud's `bird` daemon, which
  exposes the alternate versions through `NSFileVersion`.) When conflicts
  do occur we already have the merge logic to absorb them — see "Conflict
  resolution" below.
- Maps cleanly to a future iOS/iPad app — same container, same file.

**Cons / risks**

- Requires an **Apple Developer Program membership ($99/yr)** for the
  iCloud entitlement and a properly code-signed/notarised build. The app
  currently runs unsigned via `xcodebuild` for personal use; this is the
  one real cost.
- **Two specific entitlements** must be provisioned in the developer
  portal *and* listed in the app's entitlements plist:
  - `com.apple.developer.ubiquity-container-identifiers` — value must
    include the exact container identifier we commit to, e.g.
    `iCloud.com.orozcoding.cadence`. The TeamID prefix is prepended by
    Xcode signing automatically.
  - `com.apple.security.app-sandbox = true` — required for iCloud
    entitlements to function under notarisation / App Store distribution.
  A mismatch between the entitlement and what the code passes to
  `FileManager.default.url(forUbiquityContainerIdentifier:)` returns
  `nil` with **no error** — sync appears enabled but nothing is ever
  written. Phase 1 has to verify the container ID is correctly resolved
  before any other work starts.
  (Note: this is *not* the same as `com.apple.developer.ubiquity-kvstore-identifier`,
  which is the `NSUbiquitousKeyValueStore` entitlement. Option 1 does not
  use the KV store.)
- Container changes (rename, bundle ID change) are *one-way doors*: once
  shipped, renaming the container orphans existing data. We commit to a
  container name up front.
- **Conflict resolution uses `NSFileVersion`, not filesystem siblings.**
  Two Macs writing while both online (or each writing while offline, then
  reconnecting) produce conflicting versions surfaced by
  `NSFileVersion.unresolvedConflictVersionsOfItem(at:)`. Resolution flow:
  1. After every `NSMetadataQuery` update, call
     `NSFileVersion.unresolvedConflictVersionsOfItem(at: url)`.
  2. For each non-`nil` entry, open a coordinated read of its `url`,
     decode with `BackupService.decode`, run `BackupService.apply()`.
  3. Mark each version `isResolved = true`.
  4. Once all are resolved, call `NSFileVersion.removeOtherVersionsOfItem(at:)`.
  Conflict copies do **not** appear as `cadence-state 2.json` files — that
  is a third-party-cloud-provider behaviour (Option 3), not iCloud
  ubiquity-container behaviour. Treating it as such would silently
  accumulate unresolved versions forever.
- **User signs out of iCloud → container disappears from disk.** macOS
  removes `~/Library/Mobile Documents/iCloud~…~cadence/` when the user
  signs out of iCloud or revokes Drive access for the app. The transport
  must:
  - Observe `NSUbiquityIdentityDidChangeNotification` and immediately
    disable sync if the token disappears.
  - On sign-out, fall back to the local `UserDefaults` store (no crash,
    no data loss — data is already there). Surface a one-line banner in
    Settings explaining what happened.
  - Define a re-enable policy: when iCloud comes back, **prefer the local
    state** over whatever was last in iCloud (the user kept editing locally
    while signed out; that work must not be silently overwritten by a
    stale cloud snapshot). The first post-recovery write seeds the cloud
    with the local snapshot.
- **iCloud storage near full → silent write failures.** The user's iCloud
  plan is shared with Photos, Mail, backups, etc. If full,
  `NSFileCoordinator` returns an error that we must catch and surface.
  This is not a "block sync forever" condition — local writes keep
  succeeding — but the UI must tell the user *why* their data isn't
  appearing on the other Mac.
- iCloud Drive has historically had quiet sync delays measured in minutes.
  Acceptable for to-do/focus data, would not be for a chat app.
- **Schema-version forward compatibility is unspecified today.** The
  existing `BackupService.decode` rejects any `schemaVersion >
  currentSchemaVersion`. In a sync world that means: Mac A on the new
  build writes a v2 file; Mac B on the old build reads, throws
  `unsupportedSchema`, and — unless the transport explicitly handles
  that error — would either (a) crash-loop on every metadata update or
  (b) overwrite the v2 file with a downgraded v1 snapshot on its next
  write, destroying the v2-only data. **Phase 2 must add a transport-level
  rule**: if `decode` throws `unsupportedSchema`, *suspend writes
  entirely* and prompt the user to update; never let the older binary
  overwrite a newer file. Schema bumps must also be additive-only when
  possible so older binaries can ignore unknown keys rather than reject
  the whole file (a `decodeIfPresent` discipline).

**Effort estimate.** Realistic range for a first iCloud Drive integration
with proper error handling: **1–2 weeks across Phases 1–4**, broken down
roughly as:

- Phase 1 (entitlements + signing + container resolution verification):
  half a day to a full day if first-time setup, plus 24–48 h of wall-clock
  time waiting on Apple Developer Program approval after enrollment.
- Phase 2 (write path with debounce, background queue, coordinated
  writes): ~2 days.
- Phase 3 (read path with `NSMetadataQuery` + download-status gating +
  bootstrap protection): ~2–3 days. The bulk of debugging time lives
  here because `NSMetadataQuery` behaviour is opaque (`brctl` is the
  only diagnostic) and requires two physical Macs and a real iCloud
  account to validate.
- Phase 4 (`NSFileVersion` conflict resolution + sign-out / quota / schema
  edge cases): ~2–3 days.

The earlier "2–4 days" estimate covered only the happy path and is too
optimistic for a first-time iCloud integration in production.

---

### Option 2 — CloudKit private database (per-record sync via `CKSyncEngine`)

**Shape.** Each `CadenceTask`, `Folder`, focus-day entry, and the settings
blob becomes a `CKRecord` in the user's private CloudKit database.
`CKSyncEngine` (macOS 14+) tracks local changes, batches uploads, and
delivers remote changes via a push channel — all offline-capable.

**Conflict resolution.** Per-record, per-field: CloudKit gives us
client-side conflict callbacks with the server record and the local
record; we pick last-writer-wins per field (or smarter — e.g. for focus
seconds we could `max()` rather than overwrite).

**Pros**

- **Real per-record sync.** Two Macs editing different tasks while both
  online never produce a conflict copy. Two Macs editing the *same* task
  resolve at field level, not whole-file level.
- **No conflict files on disk** — the whole "iCloud Drive sometimes
  duplicates a file" class of bug disappears.
- Per-record bandwidth is tiny — uploads only the changed record, not the
  whole state blob. (`NSUbiquitousKeyValueStore` is not in scope for any
  of the three options; it was mentioned earlier only as a comparison
  point and has been removed to avoid implementer confusion.)
- Push notifications make changes appear on the other Mac in seconds, not
  minutes.

**Cons / risks**

- **Significantly more code.** Each store needs a per-record change log,
  upload queue, conflict resolver, and integration with `CKSyncEngine`'s
  state-serialisation contract. Conservatively 5–10× the surface of
  Option 1.
- Same Apple Developer Program requirement as Option 1, plus the
  CloudKit container has to be provisioned in App Store Connect.
- Existing `CadenceBackup` and `BackupService.apply` become a *secondary*
  path (export-to-file) rather than the primary. We don't throw them
  away, but their merge logic gets duplicated at the field level inside
  the sync engine.
- Schema migrations in CloudKit are coarser than in a local Codable —
  renaming a field requires a deployment to the production environment
  in CloudKit Dashboard.

**When this would be the right call.** If Cadence grew multi-user, or if
the user reported real "I lost an edit because the file synced last
write wins" pain. Today neither is true.

---

### Option 3 — User-chosen sync folder (Dropbox / Google Drive / iCloud Drive picker)

**Shape.** Settings exposes a "Sync folder" picker. The user points it at
*any* directory — typically one a cloud provider already syncs (Dropbox,
Google Drive, iCloud Drive, OneDrive, a syncthing share). The app writes
the `CadenceBackup` JSON there and watches it for external changes via:

- a `DispatchSourceFileSystemObject` on the **parent directory** observing
  `DISPATCH_VNODE_WRITE` (file-FD watchers miss the common
  staging-write-then-rename pattern used by cloud daemons — they swap a
  new inode in, so the original FD never fires), **plus**
- a short-interval timer (5–10 s) and an on-focus re-read as fallback,
  because third-party cloud daemons do not give us reliable atomic-write
  semantics.

**Pros**

- **No Apple Developer Program required.** Works in a dev build, on
  unsigned binaries, today. This matters for the current shipping model.
- **Provider-agnostic.** User picks whichever cloud they already pay for.
- Reuses 100% of `BackupService` like Option 1.
- Trivial to disable / move (just unset the path).

**Cons / risks**

- Each provider has its own quirks:
  - Dropbox creates `cadence-state (conflicted copy 2026-05-18 ...).json`
    on concurrent writes. We can scan for these and merge them in, same
    as Option 1's conflict-file handling, but it's noisier.
  - Google Drive desktop is lazy — files may not be on disk until the
    user opens the folder in Finder; we'd need to handle "file present
    in listing but not yet downloaded".
  - OneDrive `.lnk`-style placeholders behave differently again.
- File-system events from third-party cloud daemons aren't as reliable
  as iCloud's coordinated writes. The watcher-on-parent + periodic poll
  combo above is the minimum viable strategy; relying on a watcher alone
  *will* miss updates.
- Security-scoped bookmarks are required to keep folder access across
  app relaunches (the user picks the folder once; we persist the
  bookmark). Under the macOS app sandbox this also requires the
  `com.apple.security.files.user-selected.read-write` entitlement —
  without it the bookmark *silently* grants only session-scoped access,
  and the app loses folder access at next launch with no error. Add it
  to the entitlements plist as part of shipping Option 3.
- Pushes the operational responsibility onto the user — *they* picked the
  folder, *they* deal with their provider's outages.

**When this would be the right call.** Right now, while there's no
Developer Program account. Or as a *complement* to Option 1 for users who
prefer not to use iCloud.

---

## My recommendation: Option 1 (iCloud Drive ubiquity container)

**Why.**

1. **It reuses everything we already built.** The "what to sync, when to
   merge, how to roll back" questions are answered. Only "how does the
   file get from Mac A to Mac B" is new.
2. **Offline-first comes free.** iCloud Drive's contract — local file,
   background upload, sync on reconnect — is exactly the requirement.
3. **No infra, no auth, no costs.** The only fixed cost is the Apple
   Developer Program membership the user almost certainly wants anyway
   for distributing a signed macOS build.
4. **It's the smallest reversible step.** If iCloud sync proves
   insufficient (e.g. real conflicts in practice), we can upgrade to
   Option 2 (CloudKit) without changing the on-disk Codable schema, and
   we can run Option 3 (custom folder) alongside as a fallback.

**Why not Option 2 (CloudKit) first.** It's the *technically best*
answer, but it's a 5–10× cost increase against a problem we don't have
yet (no observed conflict pain, no multi-user requirement). Pick it when
the data shows we need it.

**Why not Option 3 (user-chosen folder) *as the long-term primary*.** The
only thing it genuinely buys us over Option 1 is "no Developer Program
required." Once that constraint flips, Option 1 is strictly better.
However — see Phase 0.5 below — Option 3 is the right thing to ship as
a **bridge** during the days/weeks of waiting for ADP approval and
provisioning. It costs little, surfaces any merge-logic bugs in
`BackupService` under real cross-device traffic before iCloud plumbing
is added, and can stay alive afterwards as the fallback for non-iCloud
users.

## Suggested phased delivery (if Option 1 is approved)

1. **Phase 0 (this PR).** Agreement on direction. Nothing built.
2. **Phase 0.5 (optional bridge).** Ship Option 3 as a "Sync folder"
   picker the user can point at any cloud-synced directory. Zero
   gating — works in unsigned dev builds today. Buys us real sync
   immediately and exercises `BackupService` cross-device while the
   ADP / provisioning paperwork for Option 1 is in flight.
3. **Phase 1.** App entitlement + container setup. The two entitlement
   keys (`com.apple.developer.ubiquity-container-identifiers`,
   `com.apple.security.app-sandbox`) wired into the entitlements plist
   with the exact container ID, plus a no-op Settings toggle. Acceptance
   criterion: a signed build on two Macs both resolve a non-`nil`
   `FileManager.default.url(forUbiquityContainerIdentifier:)` and can
   write & read a throwaway file.
4. **Phase 2 — write side.** Debounced
   `BackupService.makeBackup() → encode → coordinated write` on every
   store change, running on a background queue with the idle-debounce +
   max-dirty-age + on-resign-active discipline above. Also: enforce the
   "if `decode` ever throws `unsupportedSchema`, suspend writes and
   prompt the user to update" rule, even though the matching `decode`
   path lives in Phase 3 — writes must respect the contract from day 1.
5. **Phase 3 — read side.** `NSMetadataQuery` watcher →
   `startDownloadingUbiquitousItem(at:)` if status is not `.current` →
   coordinated read → `BackupService.apply()` in merge mode. Includes
   the **first-launch bootstrap gate** (see below) so a fresh Mac never
   wipes existing iCloud data.
6. **Phase 4 — robustness.**
   - `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` resolver per
     the conflict-resolution flow above.
   - `NSUbiquityIdentityDidChangeNotification` handler — disable sync,
     surface banner, fall back to local-only.
   - Surface iCloud-storage-full errors from coordinated writes.
   - End-to-end test on two real Macs.
7. **Phase 5 (optional).** Promote Phase 0.5's Option 3 from "bridge"
   to "permanent secondary transport" for users who don't want iCloud
   (one transport selected at a time; the merge code is identical).

### First-launch bootstrap (Phase 3 acceptance criterion)

Without this, the doc's read-side description has a data-loss hole on
day 1. Scenario: Mac A has months of data, enables sync, file uploads.
User opens the app on Mac B for the first time. The local `UserDefaults`
on Mac B is empty. If the debounced writer fires before the iCloud file
finishes downloading, Mac B writes an empty snapshot, iCloud replicates
it back to Mac A, **and Mac A's data is gone.**

The transport must therefore, on launch:

1. Query `NSMetadataQuery` for an existing file in the ubiquity
   container.
2. If one exists, call `startDownloadingUbiquitousItem(at:)` and **gate
   all writes** until either `NSMetadataUbiquitousItemDownloadingStatusCurrent`
   fires *or* a generous timeout (e.g. 30 s with no progress) elapses.
3. After the gate opens, apply the file in merge mode before any local
   mutation is allowed to write to the cloud copy.

This is a data-safety invariant, not a polish item.

## Open questions for the user

- **Are you willing to enroll in the Apple Developer Program** ($99/yr)?
  Option 1 and Option 2 both require it.
- **Is sync delay measured in seconds acceptable**, or do you expect
  edits to appear on the other Mac near-instantly? iCloud Drive can be
  laggy; CloudKit push is near-real-time.
- **How many devices** — just two MacBooks, or do you anticipate adding
  more (iPhone, iPad, work laptop)? Doesn't change Option 1 but informs
  whether Option 2 is worth the early investment.
