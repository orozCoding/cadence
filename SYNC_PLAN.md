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
  - ⚠️ **Known limitation for continuous sync (settings):** "settings
    taken wholesale" is fine for a one-shot import but is a silent
    conflict sink when sync runs on every change. The
    `settingsUpdatedAt: Date?` field added in Phase 2 (additive,
    `decodeIfPresent`, no schema bump) makes settings merge with
    "newest-wins-by-its-own-timestamp" — see the sign-out re-enable
    flow for details.
  - ⚠️ **Known limitation for continuous sync (deletion):** the existing
    "local-only records are preserved" rule means **deletes do not
    propagate**. Concrete failure: Mac A deletes a task and writes the
    new snapshot; Mac B reads it, sees the task is "missing" from the
    incoming file, but preserves the local copy under the local-only
    rule — and writes it back on the next sync. The deletion is
    permanently defeated. This is acceptable in the existing one-shot
    manual import (the user can re-delete on the destination Mac); it
    is a **data-correctness blocker** under continuous sync.
    **Fix landed in this plan (see "Delete propagation via tombstones"
    section below):** add a `deletedAt: Date?` field to `CadenceTask`
    and `Folder`, soft-delete records by setting that field rather
    than removing them from the array, hide tombstoned records from
    the UI, hard-purge tombstones older than a retention window (30
    days) on launch. This is small, additive, and decodes cleanly on
    old binaries via `decodeIfPresent`.
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
into a single file inside the app's iCloud ubiquity container, at a
**non-`Documents/` path** because the file is app-private state, not a
user document. Concrete location:
`~/Library/Mobile Documents/iCloud~com~orozcoding~cadence/Data/cadence-state.json`.
Apple reserves `Documents/` for user-visible files (they appear in
Files/Finder under iCloud Drive); putting our state there would clutter
the user's iCloud Drive and is the wrong scope.
macOS syncs the file across Macs signed into the same Apple ID for free.

**Read path.** On launch and whenever `NSMetadataQuery` (scoped to
`NSMetadataQueryUbiquitousDataScope` — *not* `…DocumentsScope`, since
the file lives outside `Documents/`; observing
`NSMetadataQueryDidUpdateNotification`) reports the ubiquitous file
changed, we:

1. Inspect `NSMetadataUbiquitousItemDownloadingStatusKey` on the updated
   item. If it is not `NSMetadataUbiquitousItemDownloadingStatusCurrent`,
   call `FileManager.default.startDownloadingUbiquitousItem(at:)` and wait
   for the next metadata update that signals `.current` before reading.
2. Open a coordinated read, `BackupService.decode` the file, and call
   `BackupService.apply()` — the existing merge code does the rest.

A note on `NSFilePresenter` vs `NSMetadataQuery` — they are
**complementary, not alternatives**:

- `NSMetadataQuery` is the right tool for *discovering* that a new or
  updated `cadence-state.json` has arrived from the cloud (or finished
  downloading after eviction). It is the only signal that fires when
  the iCloud daemon (`bird`) writes a remote update — `bird` does not
  go through `NSFileCoordinator`, so a presenter alone would miss
  these arrivals.
- `NSFilePresenter` is the right tool for observing
  coordinator-gated mutations *to a file the app already has open*
  (e.g., another well-behaved process editing the same file with
  `NSFileCoordinator`). For our single-file, app-private state this
  channel is rare in practice, but if we ever do hold the file open
  for editing across longer windows, registering a presenter is the
  correct way to be notified of in-flight changes.

We use `NSMetadataQuery` as the **primary** remote-change channel for
the reasons above; a presenter is optional belt-and-braces if we add
long-lived open handles later. Skipping the download-status check
inside the read path is a hang/data-loss risk whenever the Mac is low
on disk and iCloud has evicted the file under "Optimise Mac Storage" —
that part is unchanged.

**Critical read-path invariant — fold local dirty state into the merge.**
A naive `metadata-update → apply()` flow has a silent data-loss path: if
this Mac has uncommitted local edits sitting behind the debounce window
when a remote update arrives, `BackupService.apply()` will overwrite
same-`id` records with the cloud version — silently reverting the
local edits before they were ever uploaded. The read path therefore
must perform an explicit **in-memory three-way merge** rather than a
naive apply. Concrete sequence, all under the
`transport.isApplyingRemote` reentrancy flag described below:

1. **Capture remote in memory.** Open a coordinated read of the
   just-arrived `cadence-state.json` and `BackupService.decode` it
   into a local `remote: CadenceBackup` value. Do **not** touch the
   stores yet.
2. **Capture current local state.** Synchronously drain the debounce
   timer and take `local = BackupService.makeBackup()` — this is the
   in-memory state including any dirty edits made since the last
   successful write.
3. **Merge in memory, local-pending wins same-`id` collisions, tombstones
   are authoritative.** Compute `merged` by:
   - Start from `remote` (so anything `local` doesn't know about — work
     done on the other Mac — is preserved).
   - For each record (task, folder) in `local`, overwrite the
     same-`id` entry in `merged` (so this Mac's dirty edits beat the
     remote's older copy of the same record). Append local-only `id`s.
   - **Apply tombstone precedence**: for any record whose `deletedAt`
     field is non-`nil` on *either* side, set the merged record's
     `deletedAt` to the newer of the two timestamps. A tombstone on
     either side is authoritative — this is how deletes propagate
     without being silently resurrected by the local-only-wins rule.
     See "Delete propagation via tombstones" below for the model
     change and retention policy.
   - For focus-day keys present in both, prefer the higher of the two
     second counts (focus time only grows; this avoids losing minutes
     to a stale cloud day).
   - For settings, use the dedicated `settingsUpdatedAt` rule
     described under the sign-out flow.
4. **Apply `merged` to the stores** via the existing
   `BackupService.apply()` merge path. Because `merged` already
   embodies the precedence rules above, the same-`id` overwrite inside
   `apply()` is now safe — every same-`id` collision was already
   resolved in step 3 with local-pending wins.
5. **Write `merged` back to the cloud file** as one coordinated write,
   then clear the dirty flag and record the resulting blob as
   `last-written` (used by the self-echo suppression rule below). This
   single consolidated write is what the other Mac sees as the
   resolved post-merge state.
6. If any step fails (transient `NSFileCoordinator` error, container
   missing, decode failure on `remote`), **defer the entire sequence**
   rather than partially applying. The dirty flag stays set; the
   sequence re-runs on the next metadata update or the next mutation
   flush. Better a delayed import than silent partial state.

This sequence is what makes "same-id overwrite" safe in a continuous-sync
context. Without the explicit local-pending-wins step, the merge
semantics that are fine for one-shot manual imports become a data-loss
vector. With it, the only loss case is "two Macs edited the same
record while disconnected from each other" — covered by the
`NSFileVersion` conflict-resolution flow below.

**Self-echo / ping-pong suppression.** Every `apply()` writes through
the stores, which would normally re-flip the dirty flag and cause the
debounced writer to push the just-imported snapshot back out — round-trip
ping-pong on a single Mac (`apply` → `dirty` → `write` → `metadata
update` → `apply` → ...), and cross-Mac thrash when two Macs are both
online. The transport must distinguish:

- **Local mutations** (UI / keyboard / user action) → mark dirty,
  schedule debounced write.
- **Inbound applies** (this `apply()` originated from our own read
  path) → store mutations during this call **must not** re-dirty the
  transport. Implementation: a `transport.isApplyingRemote` reentrancy
  flag set around the `apply()` call; the store's "did mutate" hook
  consults the flag before touching the dirty bit.

Additionally, the writer should compare the about-to-write snapshot
against the last-successfully-written snapshot (cheap hash or byte
equality on the encoded blob) and skip the write entirely if they
match — a final guard against scheduling redundant writes for any
reason (e.g. a future code path that flips dirty without changing
logical state).

**Delete propagation via tombstones.** Without a persisted base snapshot
to diff against, "this record is in `local` but not in `remote`" is
ambiguous: did the other Mac delete it, or has the other Mac just not
seen it yet? The local-only-wins rule the existing `BackupService`
picks resolves the ambiguity in the safe direction *for one-shot
manual imports* (never lose work) but is wrong for continuous sync
(deletions never propagate; deleted records get resurrected on the
next read). We resolve this with **tombstones**, the standard answer:

- Add `deletedAt: Date?` to `CadenceTask` and `Folder` (both
  `decodeIfPresent`, so old binaries ignore it — no `schemaVersion`
  bump). A `nil` value means "live"; a non-`nil` value means "deleted
  at this timestamp."
- `TaskStore.delete(_:)` and `FolderStore.delete(_:)` change from
  `removeAll(where:)` to setting `deletedAt = Date()`. The records
  stay in the array (and therefore in the snapshot) but are filtered
  out of every UI query (`tasks(forDay:)`, `distinctDays(folderId:)`,
  etc.) by an `isLive` predicate.
- The merge algorithm in the read path treats tombstones as
  authoritative: if either side has a record with `deletedAt != nil`,
  the merged version is tombstoned. The newer of the two
  `deletedAt` timestamps wins (so an undelete on one Mac after a
  delete on the other would still need the user to repeat the
  undelete — explicit and visible, not silent).
- A **retention sweep** runs on launch: tombstones older than the
  retention window (default 30 days) are hard-removed from the local
  array. The window must be long enough that *every* user device has
  reasonably synced at least once in that span; 30 days is the
  conservative starting point. Aggressive shortening risks
  tombstones being purged before a long-offline Mac sees them, which
  would resurrect those deletions exactly the way we are trying to
  prevent.
- **Migration on first launch under sync:** any record without a
  `deletedAt` field decodes to `nil` (live) via `decodeIfPresent`. No
  one-shot migration needed; the change is purely additive.

This is the smallest change that gives correct delete semantics; the
alternative — persisting a `lastAppliedSnapshot` and computing intent
by diffing — is sound but adds a second piece of disk state that has
its own race conditions (what if the lastApplied write succeeds but
the cloud write fails?). Tombstones keep all the truth in the
snapshot itself.

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
when reachable. If both Macs edit while offline, iCloud surfaces the
divergence as **conflicting `NSFileVersion` records** on the canonical
file (not as a sibling file on disk — that is a Dropbox / third-party
behaviour, Option 3, not iCloud ubiquity). We resolve each version with
the same `mergeIn` logic (last-writer-wins per record, never destructive
to local-only records). The full resolution flow — including writing the
consolidated snapshot back before marking versions resolved — is in
"Conflict resolution" below.

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
- **Required entitlements** (must be provisioned in the developer portal
  *and* listed in the app's entitlements plist):
  - `com.apple.developer.icloud-services = ["CloudDocuments"]` — the
    service identifier that actually enables the iCloud Documents
    capability for this app. Without it, the container entitlement
    below is inert and `url(forUbiquityContainerIdentifier:)` returns
    `nil`.
  - `com.apple.developer.ubiquity-container-identifiers` — value must
    include the exact container identifier we commit to, e.g.
    `iCloud.com.orozcoding.cadence`. **Two notes on the form**:
    - In the entitlements plist you write `iCloud.com.orozcoding.cadence`
      *without* a Team ID prefix. Xcode prepends `<TEAMID>.` at sign
      time. `FileManager.url(forUbiquityContainerIdentifier:)` is then
      called with the same un-prefixed `iCloud.com.orozcoding.cadence`
      string at runtime — the framework matches it against the signed
      entitlement.
    - Do not hand-edit this in `project.pbxproj` or the entitlements
      file without understanding what Xcode is doing for you. Adding a
      stray `<TEAMID>.` prefix yourself produces a `nil` result at
      runtime with no error logged.
- **Sandboxing — a choice we are making, not a hard iCloud requirement.**
  App Sandbox (`com.apple.security.app-sandbox = true`) is *required* for
  Mac App Store distribution; for notarised direct distribution it is
  optional. We adopt it anyway because (a) future iOS/iPad expansion
  forces it, and (b) it keeps the threat surface small. Adopting it
  *does* mean we must handle the UserDefaults-migration risk explicitly
  (see Phase 1 acceptance criteria below).

  A mismatch between the entitlement and what the code passes to
  `FileManager.default.url(forUbiquityContainerIdentifier:)` returns
  `nil` with **no error** — sync appears enabled but nothing is ever
  written. Phase 1 has to verify the container ID is correctly resolved
  before any other work starts.
  (Note: none of these are the same as
  `com.apple.developer.ubiquity-kvstore-identifier`, which is the
  `NSUbiquitousKeyValueStore` entitlement. Option 1 does not use the
  KV store.)
- Container changes (rename, bundle ID change) are *one-way doors*: once
  shipped, renaming the container orphans existing data. We commit to a
  container name up front.
- **Conflict resolution uses `NSFileVersion`, not filesystem siblings.**
  Two Macs writing while both online (or each writing while offline, then
  reconnecting) produce conflicting versions surfaced by
  `NSFileVersion.unresolvedConflictVersionsOfItem(at:)`. The resolver
  must merge **all** candidates — every conflicting version, the
  currently-canonical file, and this Mac's pending local state — through
  a *single* ordered candidate set so the timestamp-ordering policy is
  uniform. Resolution flow:
  1. After every `NSMetadataQuery` update, call
     `NSFileVersion.unresolvedConflictVersionsOfItem(at: url)`. If the
     returned array is empty, this is the regular read path; otherwise
     enter the conflict path below.
  2. **Close the write gate immediately** so no in-flight debounced
     flush can push pre-merge state back to iCloud during resolution.
  3. **Capture local pending state first**: synchronously drain the
     debounce timer and take `local = BackupService.makeBackup()`. Do
     not touch any version yet.
  4. **Build one ordered candidate set**: collect, in memory:
     - every conflicting `NSFileVersion` (read each via a coordinated
       read of its `url`, decode with `BackupService.decode`), paired
       with its `modificationDate`;
     - the canonical file (`NSFileVersion.currentVersionOfItem(at: url)`),
       also paired with its `modificationDate`;
     - the captured `local` snapshot, paired with `Date()` (this Mac's
       pending edits are by definition "newer than the canonical disk
       state").
     Sort the whole set by `modificationDate` ascending (oldest first).
     Ties on `modificationDate` (rare; same-second writes from two
     Macs): break by a deterministic key (`version.persistentIdentifier`
     hash for `NSFileVersion`s; canonical and local get fixed sentinel
     keys ordered below all version hashes) so results are stable
     across runs.
  5. **Merge in memory only** — do not mutate the stores yet. Walk the
     sorted set oldest → newest, folding each snapshot into a running
     `merged` value with the same precedence rules as the regular
     read-path merge (same-`id` overwrite; tombstones authoritative;
     focus-day `max()`; settings by `settingsUpdatedAt`). Because we go
     oldest → newest, the newest snapshot's records win same-`id`
     collisions deterministically. The captured `local` snapshot sits
     at the very end of the sort (it has `Date()` as its timestamp),
     so local pending edits always win against any older version they
     conflict with.
  6. **Apply `merged` to the stores** once (under
     `transport.isApplyingRemote = true` so self-echo suppression
     fires).
  7. **Write `merged` back** as one coordinated write to
     `cadence-state.json` and verify it succeeded.
  8. Only **after** the consolidated write succeeds, mark each
     conflicting version `isResolved = true` and call
     `NSFileVersion.removeOtherVersionsOfItem(at:)`. Then re-open the
     write gate.
  Skipping step 7 is a real data-loss path: without an explicit
  post-merge write, the merged state lives only in this Mac's local
  stores until the next user mutation. If the user closes the app first,
  the other Mac never sees the resolution, and its next sync push will
  overwrite the canonical file with one of the pre-merge versions —
  silently undoing the merge.
  Skipping the "single ordered set" shape (e.g. merging the canonical
  file in a separate pass after the version loop) leaves the canonical
  file outside the timestamp policy, so its same-`id` records can win
  collisions the policy says they should lose.
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
  - Re-enable policy: when iCloud comes back, **run the same in-memory
    three-way merge as the regular read path — do not call
    `BackupService.apply()` directly on the cloud snapshot.** The other
    Mac may have continued making legitimate edits while this Mac was
    signed out; the local stores may also contain edits made offline.
    Either set, naively applied via same-`id` overwrite, would silently
    obliterate the other. The correct flow:
    1. With writes still gated, download the current cloud snapshot
       (`startDownloadingUbiquitousItem` + wait for `.current`).
    2. Decode the cloud snapshot into `remote: CadenceBackup` in
       memory. Do **not** touch the stores yet.
    3. Capture `local = BackupService.makeBackup()` of the current
       store contents (which include every offline edit made while
       signed out).
    4. Compute `merged` using the same rules as the regular read-path
       merge: same-`id` overwrite with local-pending-wins,
       **tombstone precedence** (newer `deletedAt` wins; tombstone on
       either side authoritative — so deletes made on the other Mac
       while this one was signed out still propagate), focus-day
       `max()`, and the dedicated `settingsUpdatedAt` rule.
    5. Apply `merged` to the stores once (under
       `transport.isApplyingRemote = true`).
    6. Take a fresh `makeBackup()` of the now-consolidated state and
       write it back as the first post-recovery write under
       `NSFileCoordinator`. Verify success.
    7. Only then open the write gate.

    The `settingsUpdatedAt` rule referenced in step 4: pick the side
    with the newer `settingsUpdatedAt`. This field was added in Phase
    2 as a `Date?` declared `decodeIfPresent` on `BackupSettings`,
    bumped only when a setting actually mutates. Because it is
    additive-only, no `schemaVersion` bump is required and old binaries
    that don't know about the field simply fall back to the original
    "settings replaced wholesale" behaviour. (The `unsupportedSchema`
    suspend-writes rule below applies only to *breaking* changes that
    bump `schemaVersion`; optional fields decoded with `decodeIfPresent`
    are not breaking and do not bump it. The two rules do not
    conflict.) If `settingsUpdatedAt` is missing on both sides (e.g.
    both binaries pre-date the field) the snapshot-level `exportedAt`
    is the fallback tiebreaker — known to be unsound but never worse
    than today's behaviour. A future "merge settings field-by-field
    with per-field timestamps" is an option if option (a) proves
    insufficient.

    This treats sign-out as a long offline period rather than as a
    "local is canonical" event.
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
3. **Phase 1.** App entitlement + container setup. The three iCloud-related
   entitlement keys (`com.apple.developer.icloud-services` set to
   `["CloudDocuments"]`, `com.apple.developer.ubiquity-container-identifiers`
   with the exact container ID, and the App Sandbox toggle
   `com.apple.security.app-sandbox = true`) wired into the entitlements
   plist, plus a no-op Settings toggle. Acceptance criteria — *all three
   must pass before Phase 2 starts*:

   1. A signed build on two Macs both resolve a non-`nil`
      `FileManager.default.url(forUbiquityContainerIdentifier:)` and can
      write & read a throwaway file in the container's `Data/` subpath.
   2. **Sandbox-transition data survival.** Enabling App Sandbox
      changes the effective preferences domain. Before Phase 2 ships,
      install the new sandboxed build over an existing un-sandboxed
      install and verify every `UserDefaults` key the app currently uses
      (`cadence_tasks`, `cadence_folders`, `cadence_active_folder_id`,
      `focusDailySeconds`, `weekStartsOn`, `timerFinishSound`,
      `timerStyle`, `timerDirection`, `animateDockIcon`, and any backup
      service keys) still loads correctly on first launch under the
      sandbox. If anything is lost, ship a one-shot migration shim that
      copies the pre-sandbox defaults into the sandboxed container
      *before* any other code runs at first launch.
   3. The no-op Settings toggle persists correctly and the rest of the
      app (tasks, focus, settings) behaves identically to the
      un-sandboxed build.
4. **Phase 2 — model changes + write side.** Two pieces, sequenced
   in this order so the on-disk format is right *before* anything
   starts writing it:
   1. **Model additions** (additive, all `decodeIfPresent`, no
      `schemaVersion` bump):
      - `deletedAt: Date?` on `CadenceTask` and `Folder`. `delete(_:)`
        on each store flipped from array removal to setting the
        timestamp. Every UI query filtered through an `isLive`
        predicate. Retention sweep on launch (default 30 days) that
        hard-purges stale tombstones. See "Delete propagation via
        tombstones" above.
      - `settingsUpdatedAt: Date?` on `BackupSettings`, bumped only
        when a setting mutates. Used by the read-path merge for the
        settings tiebreaker.
   2. **Debounced writer.**
      `BackupService.makeBackup() → encode → coordinated write` on
      every store change, on a background queue with the idle-debounce
      + max-dirty-age + on-resign-active discipline above. Enforce the
      "if `decode` ever throws `unsupportedSchema`, suspend writes and
      prompt the user to update" rule even though the matching
      `decode` path lives in Phase 3 — writes must respect the
      contract from day 1.
5. **Phase 3 — read side.** Wire the read pipeline exactly as the
   "Critical read-path invariant — fold local dirty state into the
   merge" section spells out:
   1. `NSMetadataQuery` watcher (scoped to
      `NSMetadataQueryUbiquitousDataScope`) fires.
   2. If `NSMetadataUbiquitousItemDownloadingStatusKey` is not
      `.current`, call `startDownloadingUbiquitousItem(at:)` and wait.
   3. Coordinated read of the file → `BackupService.decode` into a
      `remote: CadenceBackup` in memory. Do not touch the stores.
   4. Synchronously drain the debounce timer and capture
      `local = BackupService.makeBackup()`.
   5. Compute `merged` with the precedence rules (same-`id`
      local-pending-wins, tombstone-authoritative, focus-day `max()`,
      `settingsUpdatedAt` for settings).
   6. Apply `merged` once under `transport.isApplyingRemote = true`.
   7. Coordinated write of `merged` back to `cadence-state.json`.
   Includes the **first-launch bootstrap gate** (see below — gate held
   closed from process start until `NSMetadataQueryDidFinishGathering`
   fires AND the download has completed) so a fresh Mac never wipes
   existing iCloud data. A naive `decode → apply()` flow would silently
   revert dirty local edits; the in-memory merge above is what makes
   "same-id wins" safe in a continuous-sync context.
6. **Phase 4 — robustness.**
   - `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` resolver per
     the conflict-resolution flow above (including the sort-by-
     `modificationDate` tie-breaker).
   - `NSUbiquityIdentityDidChangeNotification` handler — disable sync,
     surface banner, fall back to local-only.
   - **Re-enable-after-sign-in recovery flow.** When the identity token
     returns, run the full download → in-memory merge → consolidated
     write → open-gate sequence described in the sign-out section
     above. This is scheduled here explicitly because the disable
     direction alone is not enough — without the matching enable
     direction, a re-signed-in user either loses iCloud edits made
     elsewhere or has sync silently stay off after re-login.
   - Surface iCloud-storage-full errors from coordinated writes.
   - End-to-end test on two real Macs, including the sign-out /
     sign-in round trip.
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

1. **Hold the write gate closed from process start** — before any other
   code that could trigger a debounced write runs. The gate stays shut
   until **both** of:
   - `NSMetadataQueryDidFinishGathering` has fired (i.e. the metadata
     query has completed its initial enumeration of the ubiquity
     container and we know whether a `cadence-state.json` already
     exists), and
   - the existence check + download step below have resolved.
   Without the "until gathering finishes" condition, an empty local
   snapshot can win the race: the writer flushes before
   `NSMetadataQuery` has discovered the existing cloud file, and the
   empty snapshot overwrites it.
2. Once gathering finishes, inspect the results. If a
   `cadence-state.json` exists, call `startDownloadingUbiquitousItem(at:)`
   and keep the gate shut until
   `NSMetadataUbiquitousItemDownloadingStatusCurrent` fires. The gate
   must **not** silently open on a timeout — opening it without the
   download having completed re-introduces the exact empty-snapshot
   overwrite hazard this section exists to prevent.
3. If the download has not completed after a long wait (e.g. 30 s with
   no progress), surface a blocking choice in the UI:
   - **"Wait and keep trying"** — the default; keeps the gate shut and
     keeps retrying the download. The user can still read existing
     local data; only the *write side* is blocked.
   - **"This Mac is the new source of truth"** — explicit user consent
     to open the gate and let the local (possibly empty) state become
     canonical. This is the only path that may overwrite the cloud
     copy without first reading it.
4. Once `.current` fires, apply the file in merge mode before any local
   mutation is allowed to write to the cloud copy, then open the gate.

If gathering finishes and **no** `cadence-state.json` exists at all
(genuinely first-ever launch across all the user's Macs), the gate
opens immediately — there is nothing to overwrite. This is the only
path that opens the gate without a downloaded file.

**The same gate also applies on mid-session toggle-on.** When the user
flips "Sync via iCloud" on from Settings while the app is already
running, the transport must run this *same* closed-write bootstrap
sequence — enumerate metadata, wait for
`NSMetadataQueryDidFinishGathering`, download and apply any existing
cloud snapshot, then open the gate. A user with an existing cloud
file (from another Mac) who enables sync mid-session must not have
their cloud data overwritten by their newly-enabled-but-still-empty
local sync state. Treat enable-while-running as identical to
first-launch for gate-sequencing purposes.

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
