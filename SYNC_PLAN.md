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
    `settingsUpdatedAt: Date?` field added in Phase 2 (one of three
    fields landing together under a `schemaVersion: 2` bump — see
    "Why these additions bump `schemaVersion`" below) makes settings
    merge with "newest-wins-by-its-own-timestamp" — see the sign-out
    re-enable flow for details.
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
    days) on launch. Ships under the `schemaVersion: 2` bump (see
    "Why these additions bump `schemaVersion`" below) so v1 binaries
    can't accidentally strip the field and resurrect deletes on
    write.
  - ⚠️ **Known limitation for continuous sync (same-record edits):**
    same-`id` task/folder collisions in the existing `apply()`
    unconditionally overwrite the local record with the incoming
    copy. In a continuous-sync world that flips the loss direction
    based on which Mac happens to sync last. **Fix landed in this
    plan (see "Per-record conflict resolution via `updatedAt`"
    section below):** add `updatedAt: Date` to `CadenceTask` and
    `Folder` (ships under the same `schemaVersion: 2` bump as the
    other two new fields), bump on every mutation, resolve same-`id`
    collisions by newer-wins.
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

**Read path (overview — full specification is "Critical read-path
invariant" below).** Trigger: `NSMetadataQuery` (scoped to
`NSMetadataQueryUbiquitousDataScope` — *not* `…DocumentsScope`, since
the file lives outside `Documents/`) reports the ubiquitous file
changed via `NSMetadataQueryDidUpdateNotification`. From there:

1. Inspect `NSMetadataUbiquitousItemDownloadingStatusKey` on the updated
   item. If it is not `NSMetadataUbiquitousItemDownloadingStatusCurrent`,
   call `FileManager.default.startDownloadingUbiquitousItem(at:)` and wait
   for the next metadata update that signals `.current` before reading.
2. Run the in-memory three-way merge sequence — capture remote in
   memory, capture local pending state, compute `merged` with the
   precedence rules, apply once, write back. **The naive
   "decode → BackupService.apply() directly" flow is unsafe** because
   it silently overwrites dirty local edits; do not implement it. The
   full sequence and its rationale are specified in "Critical read-path
   invariant — fold local dirty state into the merge" below, and that
   section is the single source of truth for the read path.

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
naive apply.

**Store-serialization invariant — capture, merge, and apply must run
on the store's actor with no interleaving mutations.** All three
stores (`TaskStore`, `FolderStore`, `FocusTimeStore`) are
`@MainActor`-isolated today, which makes this almost free: the entire
sequence below — *from* `capture local` *through* `apply(merged)` —
runs as one main-actor turn. The transport must enforce this:

- The merge entrypoint is a single `@MainActor` function (e.g.
  `runMergeSequence(remoteData: Data)`). All steps below execute
  inside that function, on the main actor, with no `await` that
  releases control between capture and apply. The remote download
  and coordinated read happen *before* the function runs, on a
  background queue; the function receives the already-decoded bytes.
- If background-queue work is needed mid-sequence (it shouldn't be —
  the merge is pure in-memory computation), it must complete and
  return its result before any store mutation, so the actor never
  releases between capture and apply.
- Same invariant applies to the conflict resolver and the sign-in
  recovery flow — every merge path runs as one main-actor turn.

Without this invariant, a same-`id` user edit landing between
`capture` and `apply` is silently overwritten by the now-stale
`merged` snapshot. With it, the actor's serialization guarantee makes
that race impossible: the user mutation either lands *before* capture
(and is part of `local`) or *after* apply (and re-dirties the
transport normally).

Concrete sequence (the `transport.isApplyingRemote`
reentrancy flag described under "Self-echo / ping-pong suppression"
below is scoped narrowly — set **only** around the `apply(merged)`
call in step 4, not around the whole sequence. The earlier steps
either don't mutate the stores at all or are pure in-memory reads, so
wrapping them in the flag would suppress legitimate user mutations
that *should* re-dirty the transport for the next write cycle. The
serialization invariant above is what protects capture/merge/apply
atomicity — the flag is only for self-echo suppression):

1. **Close the write gate and drain in-flight writers.** Before
   anything else, flip the write gate to "closed" so no new
   debounced writes can be dispatched. Then `await` any *currently
   running* background writer (one whose `coordinated write` is
   already in progress at the moment the gate closed) — wait for it
   to finish its current coordinated write and clear its busy flag
   before proceeding. Draining only the debounce *timer* (the
   previous wording) is not enough: a write that was dispatched a
   moment earlier and is now mid-flight on a background queue can
   still land *after* the merged write below and clobber the
   resolved cloud snapshot with stale pre-merge state. Same gate
   discipline used by the `NSFileVersion` resolver and the sign-in
   recovery flow.
2. **Capture remote in memory.** Open a coordinated read of the
   just-arrived `cadence-state.json` and `BackupService.decode` it
   into a local `remote: CadenceBackup` value. Do **not** touch the
   stores yet.
3. **Capture current local state.** Now that no writer can race us,
   take `local = BackupService.makeBackup()` — this is the in-memory
   state including any dirty edits made since the last successful
   write.
4. **Merge in memory using per-record timestamps. Newer `updatedAt`
   wins same-`id` collisions; tombstones are authoritative.** Compute
   `merged` by:
   - Start from `remote` (so anything `local` doesn't know about —
     work done on the other Mac — is preserved).
   - For each `id` present in both `local` and `remote`, compare the
     two records' `updatedAt` timestamps (see "Per-record conflict
     resolution via `updatedAt`" below for the model change). Take
     the side with the strictly-newer `updatedAt`. On equal
     timestamps (no change since last sync, or rare same-second edit
     on both sides), prefer `local` — this Mac's view is authoritative
     for an unchanged record, and a same-instant double-edit is
     resolved deterministically. **Do not blanket-prefer `local`** —
     that would silently discard legitimate remote edits made
     between this Mac's last sync and now.
   - For each `id` in `local` only, append it to `merged`. (It is
     either a record this Mac created since last sync, or one this
     Mac never saw the remote-side delete for — the tombstone rule
     below handles the latter.)
   - **Apply tombstone precedence**: for any record whose `deletedAt`
     field is non-`nil` on *either* side, set the merged record's
     `deletedAt` to the newer of the two timestamps. A tombstone on
     either side is authoritative — this is how deletes propagate
     without being silently resurrected. See "Delete propagation via
     tombstones" below for the model change and retention policy.
   - For focus-day keys present in both, prefer the higher of the two
     second counts (focus time only grows; this avoids losing minutes
     to a stale cloud day).
   - For settings, use the dedicated `settingsUpdatedAt` rule
     described under the sign-out flow.
   - **For `activeFolderID`: split between local store and merged blob,
     to avoid ping-pong.** Which folder is open on *this* Mac is a UI
     selection, not user data — there's no reason for Mac B to take
     Mac A's active folder over Mac B's own. Two concrete rules
     enforce this without causing the wire format to ping-pong
     between the two Macs' selections:
     1. **Local store: never overwritten from sync.** The live
        `FolderStore.activeFolder` keeps whatever this Mac selected.
        Matches the existing one-shot `BackupService.apply()` which
        already leaves `activeFolderID` alone with a "destination
        device keeps its current context" comment.
     2. **Merged blob: preserve the *incoming remote's*
        `activeFolderID`, not the local selection.** Set
        `merged.activeFolderID = remote.activeFolderID` when building
        `merged` for the write-back. This is the critical rule that
        prevents ping-pong: if Mac A has folder X active and Mac B
        has folder Y, naively writing local-Y back when reading
        remote-X would cause Mac A to write X back when reading the
        new Y, and so on forever (self-echo suppression doesn't help
        — each blob genuinely differs). Preserving the incoming value
        means whatever the cloud already had survives the write-back
        round trip; nobody pings-pongs; the field still carries a
        meaningful value (the active folder of whichever Mac last
        wrote a non-active-folder change).
     Edge case: if this Mac's local `activeFolderID` points at a
     folder that the merge result has tombstoned, the local store
     falls back to `.generalFolderID` — same fallback the codebase
     already uses for missing folders. (This is a local-store
     transition, not a `merged` blob change.)
5. **Apply `merged` to the stores** via the existing
   `BackupService.apply()` merge path. Because `merged` already
   embodies the precedence rules above, the same-`id` overwrite inside
   `apply()` is now safe — every same-`id` collision was already
   resolved in step 4 with the explicit `updatedAt` policy.
6. **Write `merged` back to the cloud file** as one coordinated write.
7. **Clear the dirty flag and record the `merged` blob as
   `last-written`** (used by the self-echo suppression rule below).
   This single consolidated write is what the other Mac sees as the
   resolved post-merge state.
8. **Reopen the write gate** (closed at step 1) so the debounce
   writer can resume normal operation.
9. If any step fails (transient `NSFileCoordinator` error, container
   missing, decode failure on `remote`), **defer the entire sequence**
   rather than partially applying. The dirty flag stays set; the
   sequence re-runs on the next metadata update or the next mutation
   flush. Better a delayed import than silent partial state. The
   write gate **must** be reopened on the failure path too — leaving
   it permanently closed would silently disable sync.

This sequence is what makes "same-id overwrite" safe in a continuous-sync
context. Without the explicit per-record `updatedAt` step, the merge
semantics that are fine for one-shot manual imports become a data-loss
vector — either direction (`local` blanket-wins ⇒ remote edits silently
lost; `remote` blanket-wins ⇒ local dirty edits silently lost). With it,
the only loss case is "two Macs edited the same record while
disconnected from each other and the later edit overrode the earlier" —
that's `NSFileVersion` conflict territory, handled below.

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

**Per-record conflict resolution via `updatedAt`.** Without a
per-record mutation timestamp, the merge code cannot tell a "dirty
local edit" from "old unchanged local record" — they look identical
in `local = makeBackup()`. Blanket-preferring `local` for same-`id`
collisions would silently discard any legitimate remote edit made
between this Mac's last sync and now (e.g. Mac B edited task X 10
minutes ago and uploaded it; Mac A still holds the older copy
locally). To fix this:

- Add `updatedAt: Date` to `CadenceTask` and `Folder`. Declare as
  `decodeIfPresent` with a fallback of `createdAt` for any record
  missing the field (legacy data written by binaries from before
  Phase 2). The struct-level decode is rollout-safe, but the **sync
  semantics are not** — see "Why these additions bump
  `schemaVersion`" below.
- Every mutating method on `TaskStore` / `FolderStore` (`add`,
  `update`, `toggle`, `delete`) sets `updatedAt = Date()` on the
  affected record before saving. The retention sweep that purges
  stale tombstones does **not** bump `updatedAt` — it is a local-only
  hard-delete and shouldn't masquerade as a user edit.
- Same-`id` merge across every path (regular read, `NSFileVersion`
  resolver, sign-in recovery) compares `updatedAt`s and takes the
  newer side. Ties (same instant on both Macs, or unchanged on both
  sides since last sync) prefer `local` — deterministic and
  appropriate because an unchanged record is the same regardless of
  side.
- Clock-skew caveat: `updatedAt` uses each Mac's local `Date()`. If
  one Mac's clock is materially wrong, its edits can over-win or
  under-win. We accept this — both Macs are the same user's
  machines, both run macOS time sync against Apple's NTP servers,
  and skew measured in seconds is unlikely to alter the outcome of
  any merge in practice. CloudKit (Option 2) avoids this by
  timestamping server-side; if clock skew ever proves to be a real
  problem in the field, that is a reason to revisit Option 2 rather
  than to add server timestamps to Option 1.

This is the per-record analogue of `settingsUpdatedAt`; together they
give every part of the synced state a defined conflict policy.

**Delete propagation via tombstones.** Without a persisted base snapshot
to diff against, "this record is in `local` but not in `remote`" is
ambiguous: did the other Mac delete it, or has the other Mac just not
seen it yet? The local-only-wins rule the existing `BackupService`
picks resolves the ambiguity in the safe direction *for one-shot
manual imports* (never lose work) but is wrong for continuous sync
(deletions never propagate; deleted records get resurrected on the
next read). We resolve this with **tombstones**, the standard answer:

- Add `deletedAt: Date?` to `CadenceTask` and `Folder` (both
  `decodeIfPresent`-compatible at the decoder layer, but ships
  under the `schemaVersion: 2` bump so older binaries don't
  participate in sync and silently strip the field on write — see
  "Why these additions bump `schemaVersion`" above). A `nil` value
  means "live"; a non-`nil` value means "deleted at this timestamp."
- `TaskStore.delete(_:)` and `FolderStore.delete(_:)` change from
  `removeAll(where:)` to setting `deletedAt = Date()`. The records
  stay in the array (and therefore in the snapshot) but are filtered
  out of every UI query (`tasks(forDay:)`, `distinctDays(folderId:)`,
  etc.) by an `isLive` predicate.
- **Folder-delete cascade explicit rule.** Today
  `FolderStore.delete(_:)` calls `TaskStore.deleteAll(inFolder:)`
  which hard-removes every task in the folder. Under tombstoning
  that becomes: **each child task is individually tombstoned** by
  the same call — `deletedAt = Date()` and `updatedAt = Date()` set
  on every child task — and the folder itself is tombstoned with
  the same timestamp. Three reasons each child gets its own
  tombstone (rather than "live tasks under a tombstoned folder" or
  "hard-delete children but tombstone folder"):
  1. Other Macs only see what's in the snapshot. A live task whose
     folder is tombstoned would still surface in the UI on a Mac
     that hasn't yet swept the orphan-folder recovery path —
     resurrecting the data the user just deleted.
  2. Hard-removing children locally and tombstoning only the folder
     breaks the rule that the other Mac learns about deletions
     through tombstones; the child task would silently re-sync from
     the other Mac's still-live copy on the next merge.
  3. Cascade-tombstoning keeps the per-record `updatedAt` rule
     coherent — a task that was both edited on Mac A and
     cascade-deleted on Mac B at the same instant resolves through
     the normal tombstone-precedence + `updatedAt` comparison,
     instead of falling into an undefined "folder said delete but
     task said keep" mode.
  All cascade tombstones share the same `Date()` value (captured
  once per cascade call) so the post-deletion snapshot has a
  consistent timestamp shape.
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

**Why these additions bump `schemaVersion`.** All three new fields
(`updatedAt`, `deletedAt`, `settingsUpdatedAt`) are additive on the
*decoder* side — `decodeIfPresent` keeps the existing one-shot import
path working unchanged on legacy files. But the *sync* contract is
broken if an older binary participates after the fields ship:

- An older binary's `Encodable` simply doesn't emit the new fields
  on write. A v1-aware binary that picks up a v2 cloud file, decodes
  it, edits something, and writes back, would strip `updatedAt`,
  `deletedAt`, and `settingsUpdatedAt` from every record in the
  snapshot. Tombstones would resurrect; updated records would look
  stale; settings would silently last-writer-wins again.
- A v1 binary reading a v2 file would still treat tombstoned records
  as live and surface them in the UI. The user would see "deleted"
  tasks reappear.

Therefore Phase 2 **does bump `schemaVersion` from 1 to 2** even
though the field additions are individually decode-compatible. The
bump is the gate, not the field shape. Combined with the existing
"if `decode` throws `unsupportedSchema`, suspend writes and prompt
the user to update" transport rule, this gives correct mixed-version
behaviour:

- v2 binary writes v2 files. Other v2 binaries read them normally.
- v1 binary attempts to read v2 file → `unsupportedSchema` → writes
  suspended → user sees the "please update" banner. v1 keeps working
  locally on its own UserDefaults state; no sync until upgrade.
- v1 binary writes v1 files (it can't do otherwise) → its writes
  never land in the v2 cloud snapshot because the transport on v1 is
  already suspended.
- Once every Mac is on v2, sync resumes normally.

The user-facing cost is one "update Cadence to enable sync"
notification on the lagging Mac during a staggered upgrade — small
and well-understood, much better than silent data loss.

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
  2. **Close the write gate and drain any in-flight background
     writer.** Flip the gate to "closed" so no new debounced writes
     can be dispatched, then `await` any *currently running*
     background writer (one whose `coordinated write` is already in
     progress) to finish and clear its busy flag. Same rule as the
     regular read path — draining only the debounce timer is not
     enough; a writer that was dispatched a moment earlier can be
     mid-flight on a background queue and would land after the
     merged write below, clobbering the resolved snapshot with stale
     pre-merge state.
  3. **Capture local pending state**: now that no writer can race
     us, take `local = BackupService.makeBackup()`. Do not touch any
     version yet.
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
     read-path merge:
     - Same-`id` task/folder collisions resolve by per-record
       `updatedAt` (newer wins). On equal `updatedAt`:
       1. If one of the colliding candidates is the captured `local`
          snapshot, `local` wins — same rule as the regular read
          path and the sign-in recovery flow, so all three merge
          paths agree.
       2. If both candidates are non-local (two different
          `NSFileVersion`s or one version + the canonical file), use
          the **candidate ordering already defined in step 4**: the
          one that appears *later* in the oldest→newest sort wins
          (higher `modificationDate`; ties on `modificationDate`
          broken by `persistentIdentifier` hash with canonical/local
          taking fixed sentinel keys). Reusing that ordering keeps
          the resolver deterministic across runs and avoids
          introducing a second ordering policy that could disagree
          with the first.
     - Tombstones authoritative; `deletedAt` precedence as above.
     - Focus-day collisions resolve by `max()`.
     - Settings resolve by `settingsUpdatedAt`.
     - `activeFolderID`: local store unaffected (per the read-path
       rule); in the `merged` blob, preserve the **canonical
       (non-conflicting) file's** `activeFolderID` — the one we read
       at step 4 alongside the conflict versions. This is the
       resolver's equivalent of "preserve incoming remote's value"
       and keeps the field from ping-ponging post-conflict.
     The captured `local` snapshot sits at the end of the sort (its
     overall-snapshot timestamp is `Date()`), so it gets the last
     pass through the fold. But the per-record `updatedAt` rule
     means a record in `local` only wins same-`id` collisions if its
     own `updatedAt` is genuinely newer — an unchanged old record in
     `local` no longer over-wins a newer remote edit just because
     its containing snapshot is "fresher."
  6. **Apply `merged` to the stores** once (under
     `transport.isApplyingRemote = true` so self-echo suppression
     fires).
  7. **Write `merged` back** as one coordinated write to
     `cadence-state.json` and verify it succeeded.
  8. **After the write succeeds, clear the dirty flag and record the
     `merged` blob as `last-written`** — same bookkeeping the
     regular read path does. Without this, the debounce writer can
     fire immediately after step 9's gate reopen, take a fresh
     `makeBackup()` (which re-serialises this Mac's local
     `activeFolderID` because `apply()` doesn't touch it), and
     overwrite the merged value we just wrote — re-introducing the
     ping-pong.
  9. Only **after** the consolidated write succeeds *and* the
     dirty-flag/last-written bookkeeping is done, mark each
     conflicting version `isResolved = true` and call
     `NSFileVersion.removeOtherVersionsOfItem(at:)`. Then re-open
     the write gate.
  10. **Failure path: always reopen the write gate** before returning,
     even if any step above threw (decode failure on a version,
     coordinator error, etc.). Leaving the gate permanently closed
     would silently disable sync forever. On failure, defer the
     resolution (versions stay unresolved, will retry on the next
     metadata update) and let the writer resume on the unchanged
     local state. Same rule as the regular read path.
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
    **close the write gate, await any in-flight background writer to
    finish (same drain rule as the regular read path), and then
    disable sync** if the token disappears. Closing the gate before
    awaiting prevents new writes from being dispatched after sign-out
    is noticed; awaiting the in-flight writer ensures we don't return
    to the user with a write still mid-flight that may target a
    container that's about to disappear.
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
       merge: same-`id` task/folder collisions resolved by per-record
       `updatedAt` (newer wins; ties prefer local), **tombstone
       precedence** (newer `deletedAt` wins; tombstone on either side
       authoritative — so deletes made on the other Mac while this
       one was signed out still propagate), focus-day `max()`, the
       dedicated `settingsUpdatedAt` rule, and `activeFolderID` split
       (local store keeps its current folder selection regardless of
       what the cloud says; the `merged` blob preserves the
       incoming-remote's `activeFolderID` to avoid the ping-pong
       described in the regular read path).
    5. Apply `merged` to the stores once (under
       `transport.isApplyingRemote = true`).
    6. Write the already-computed `merged` snapshot directly (the
       same one passed to `apply()` in step 5) back to the cloud
       file under `NSFileCoordinator`. **Do not call
       `makeBackup()` here** — `apply()` intentionally leaves the
       live `FolderStore.activeFolder` untouched, so a fresh
       `makeBackup()` would re-serialise this Mac's *local*
       `activeFolderID` and reintroduce the cross-Mac ping-pong the
       split policy is designed to prevent. The pre-computed
       `merged` already has the correct
       `activeFolderID = remote.activeFolderID`; write that exact
       value. (Same rule applies in the regular read path and the
       `NSFileVersion` resolver — write `merged`, never a
       post-apply `makeBackup()`.) Verify the coordinated write
       succeeded before moving on.
    7. **Clear the dirty flag and record the `merged` blob as
       `last-written`** — same bookkeeping as the regular read path
       and the `NSFileVersion` resolver. Without this, the moment
       step 8 reopens the write gate, the debounce writer can fire
       a fresh post-gate `makeBackup()` (which re-serialises this
       Mac's local `activeFolderID` because `apply()` doesn't touch
       it) and overwrite the merged value we just wrote, undoing
       the recovery.
    8. Only then open the write gate.
    9. **Failure path: always reopen the write gate** before
       returning, even if any step above threw (download failed,
       decode failed, coordinated write failed). Without this, a
       transient error during recovery would leave sync silently
       locked off forever. On failure, defer the recovery and let
       the next `NSMetadataQuery` update retry from step 1.

    The `settingsUpdatedAt` rule referenced in step 4: pick the side
    with the newer `settingsUpdatedAt`. This field was added in Phase
    2 as a `Date?` declared `decodeIfPresent` on `BackupSettings`,
    bumped only when a setting actually mutates. It ships together
    with `updatedAt` and `deletedAt` under the **`schemaVersion: 2`
    bump** — see "Why these additions bump `schemaVersion`" above for
    why decode-compatible additive fields still need a version gate in
    a sync context (older binaries would silently strip them on
    write). The `unsupportedSchema` suspend-writes rule does the
    gating: v1 binaries can't participate in the v2 cloud snapshot
    until upgraded. If `settingsUpdatedAt` is missing on both sides of
    a merge between two v2 binaries (e.g. settings hasn't been
    touched since upgrade), the snapshot-level `exportedAt` is the
    fallback tiebreaker — known to be unsound for settings, but
    bounded to "settings hasn't been mutated since upgrade so the
    blanket-overwrite outcome equals what either side would produce."
    A future "merge settings field-by-field
    with per-field timestamps" is the more invasive follow-on if the
    snapshot-level `settingsUpdatedAt` approach above proves
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
    on concurrent writes. We can scan for these sibling files and feed
    them through the same merge logic Option 1 uses on `NSFileVersion`
    candidates (in-memory three-way merge, per-record `updatedAt`,
    tombstone precedence, etc.), then delete the duplicates once
    merged. The merge *engine* is shared with Option 1; the *discovery*
    mechanism — filesystem siblings vs `NSFileVersion` — is Option 3's
    own and is noisier than Apple's coordinated-write contract.
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
   starts writing it.

   > ⚠️ **Shippability gate:** the build at the end of Phase 2 is
   > **NOT shippable to users.** Shipping a writer without a reader
   > and bootstrap gate is the exact empty-snapshot data-loss path
   > the bootstrap section exists to prevent — a fresh or secondary
   > device would write local-or-empty state to iCloud before ever
   > reading the existing cloud snapshot. Phase 2 lands behind a
   > **default-off feature flag** (`CADENCE_ICLOUD_SYNC=1` env var or
   > equivalent debug-only switch) so it can be tested locally on one
   > Mac, but the toggle in Settings stays hidden and the writer
   > stays inert in release builds until Phase 3 is complete and
   > verified end-to-end across two Macs. The first user-facing
   > release of Option 1 is Phase 3 + Phase 4 landing together.

   1. **Model additions + `schemaVersion: 2` bump** (all fields are
      individually `decodeIfPresent`-compatible on the decoder side,
      but the *bump itself* is what gates older binaries out of sync
      so they can't silently strip the new fields on write; see "Why
      these additions bump `schemaVersion`" above):
      - **Bump `CadenceBackup.currentSchemaVersion` from 1 to 2.**
        This is the gate. Without it, a v1 binary that happens to
        decode a v2 file (via the existing tolerant decoder) would
        re-emit a snapshot missing `updatedAt` / `deletedAt` /
        `settingsUpdatedAt` and break every merge guarantee.
      - `updatedAt: Date` on `CadenceTask` and `Folder`. Bumped by
        every mutating method on `TaskStore` / `FolderStore` (`add`,
        `update`, `toggle`, plus the soft-delete `delete`). Fallback
        for legacy v1 records missing the field: decode via
        `decodeIfPresent` and substitute `createdAt`. The retention
        sweep that purges tombstones does **not** bump `updatedAt`.
        Used by the read-path merge for the per-record `updatedAt`
        tiebreaker; see "Per-record conflict resolution via
        `updatedAt`" above.
      - `deletedAt: Date?` on `CadenceTask` and `Folder`. `delete(_:)`
        on each store flipped from array removal to setting the
        timestamp (and bumping `updatedAt` in the same call). Every
        UI query filtered through an `isLive` predicate. Retention
        sweep on launch (default 30 days) that hard-purges stale
        tombstones. See "Delete propagation via tombstones" above.
      - `settingsUpdatedAt: Date?` on `BackupSettings`, bumped only
        when a setting mutates. Used by the read-path merge for the
        settings tiebreaker.
      - **User-facing upgrade path:** a Mac that hits a v2 cloud
        snapshot while still on v1 shows the existing "please update
        Cadence to enable sync" banner (triggered by the existing
        `unsupportedSchema` suspend-writes rule). It keeps working
        locally on its own UserDefaults state; no sync until upgrade.
        This is the intentional cost of the bump and is the right
        trade vs. silent data loss.
   2. **Debounced writer (behind feature flag).**
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
   3. **Close the write gate** and await any in-flight background
      writer to finish (not just drain the timer — a writer that was
      dispatched before the gate closed can be mid-coordinated-write
      and would clobber the merged write below if not drained).
   4. Coordinated read of the file → `BackupService.decode` into a
      `remote: CadenceBackup` in memory. Do not touch the stores.
   5. Capture `local = BackupService.makeBackup()`.
   6. Compute `merged` with the precedence rules (same-`id` resolved
      by per-record `updatedAt`, tombstone-authoritative, focus-day
      `max()`, `settingsUpdatedAt` for settings, `activeFolderID =
      remote.activeFolderID`).
   7. Apply `merged` once under `transport.isApplyingRemote = true`.
   8. Coordinated write of `merged` back to `cadence-state.json`.
   9. Clear dirty flag; record `merged` as `last-written`; reopen
      the write gate. (Gate reopen runs on both success and failure
      paths so sync can't silently lock itself off.)
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
