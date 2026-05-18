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

**Read path.** On launch and whenever an `NSMetadataQuery` (or
`NSFilePresenter`) reports the ubiquitous file changed, we
`BackupService.decode` it and call `BackupService.apply()` — the existing
merge code does the rest.

**Write path.** Any mutating call on a store flips a "dirty" flag. A
debounced writer (~2 s idle, or on `applicationWillResignActive`) takes a
fresh `makeBackup()`, encodes it, and writes the file under
`NSFileCoordinator` so iCloud sees an atomic update.

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
- **Conflict copies are rare in practice** because iCloud uses coordinated
  writes; when they happen we already have the merge logic to absorb them.
- Maps cleanly to a future iOS/iPad app — same container, same file.

**Cons / risks**

- Requires an **Apple Developer Program membership ($99/yr)** for the
  iCloud entitlement and a properly code-signed/notarised build. The app
  currently runs unsigned via `xcodebuild` for personal use; this is the
  one real cost.
- Container changes (rename, bundle ID change) are *one-way doors*: once
  shipped, renaming the container orphans existing data. We commit to a
  container name up front.
- Two Macs writing **simultaneously while both online** can still produce
  an iCloud conflict file (`cadence-state 2.json`). Mitigation: detect
  files matching `cadence-state*.json`, decode each, merge all of them,
  then delete the duplicates. (Same code as a regular import, run in a
  loop.)
- iCloud Drive has historically had quiet sync delays measured in minutes.
  Acceptable for to-do/focus data, would not be for a chat app.

**Effort estimate.** ~1 small PR for the transport (writer + watcher +
toggle) plus a small PR for the entitlement & signing setup. Probably
2–4 days of focused work.

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
- Much higher quotas than `NSUbiquitousKeyValueStore`, and per-record
  bandwidth is tiny.
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
the `CadenceBackup` JSON there and watches it via
`DispatchSourceFileSystemObject` for external changes.

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
  as iCloud's coordinated writes. We'd want both a watcher *and* a
  periodic re-read on app focus to be safe.
- Security-scoped bookmarks are required to keep folder access across
  app relaunches (the user picks the folder once; we persist the
  bookmark).
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

**Why not Option 3 (user-chosen folder) first.** The only thing it
genuinely buys us over Option 1 is "no Developer Program required." If
that constraint flips, Option 1 is strictly better. Worth shipping
*later* as a secondary transport for users who don't want iCloud, but
not the right primary.

## Suggested phased delivery (if Option 1 is approved)

1. **Phase 0 (this PR).** Agreement on direction. Nothing built.
2. **Phase 1.** App entitlement + container setup. One-liner Settings
   toggle that does nothing yet. Verify a signed build can write to and
   read from the ubiquity container on two Macs.
3. **Phase 2.** Hook up the write side: debounced
   `BackupService.makeBackup() → encode → coordinated write` on every
   store change.
4. **Phase 3.** Hook up the read side: `NSMetadataQuery` watcher →
   decode → `BackupService.apply()` (merge mode).
5. **Phase 4.** Conflict-file sweeper: detect `cadence-state*.json` siblings,
   merge each in, delete duplicates after success.
6. **Phase 5 (optional).** Add Option 3 as a secondary transport for
   non-iCloud users.

## Open questions for the user

- **Are you willing to enroll in the Apple Developer Program** ($99/yr)?
  Option 1 and Option 2 both require it.
- **Is sync delay measured in seconds acceptable**, or do you expect
  edits to appear on the other Mac near-instantly? iCloud Drive can be
  laggy; CloudKit push is near-real-time.
- **How many devices** — just two MacBooks, or do you anticipate adding
  more (iPhone, iPad, work laptop)? Doesn't change Option 1 but informs
  whether Option 2 is worth the early investment.
