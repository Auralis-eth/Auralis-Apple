# P0-451 Tickets And Session Handoff

## Summary

Implement a minimal music library index with local persistence and refresh receipts, deriving the first library from the existing SwiftData-backed local `NFT` store for Phase 0.

## Ticket Status

In progress.

## Execution Checklist

### 1. Confirm scope and active seams

- [x] Re-read `P0-451-Strategy.md` and `P0-451-Dependency-Note.md` before coding.
- [x] Confirm the active Music surface is the `MusicApp/AI/` path, not `MusicApp/OLD/`.
- [x] Confirm where the first index will be consumed in the live shell: Music first, then Home/Search if that integration is still part of the initial slice.
- [x] Confirm the existing receipt path to extend for music index refresh activity instead of introducing a new logger shape.

Findings:

- The mounted Music tab in `MainTabView` uses `NFTMusicPlayerApp` from `MusicApp/AI/V1/App.swift`; `MusicApp/OLD/MusicApp.swift` is commented legacy code and is not on the active route.
- The current live Music library is still NFT-query-backed inside `NFTMusicPlayerLibraryView`, filtered from `NFT` records by `nft.isMusic()`. There is not yet a separate music index model feeding the mounted Music surface.
- The current shell already exposes a narrow library seam in `ShellServiceHub` through `ShellLibraryContextProviding`, but today it only reports playlist count and scoped receipt count. `P0-451` can either extend that seam or add a sibling music-library seam rather than wiring ad hoc queries into more views.
- Home currently links to Music through `router.showMusicLibrary()` but does not yet consume a dedicated music index.
- Search currently builds its local index from `NFT` and `EOAccount` only; it does not yet consume music-library data.
- The existing receipt seam to extend is `ReceiptEventLogger`, created from `services.receiptStoreFactory(modelContext)` in the shell/context path. `P0-451` should add music-library refresh/index events there instead of inventing a second logging mechanism.
- There is already persisted music-adjacent storage in `Playlist` / `PlaylistStore`, but that model represents playlists with track membership, not a general library index. It is useful context, but it is not by itself the missing `P0-451` library index.

### 2. Define the first library index model

- [x] Define the minimum stored/indexed shape needed for a usable Phase 0 music library.
- [x] Keep the model broad enough that `P0-452` can add collection/detail behavior without forcing a storage rewrite.
- [x] Decide what is source data, what is derived index data, and what must persist locally across relaunch.
- [x] Document any intentionally deferred fields so they do not quietly leak into this ticket.

Model definition:

- The first music library index should be a dedicated SwiftData-backed index model derived from locally stored `NFT` records where `nft.isMusic()` is true.
- The index is not a replacement for `NFT`; it is a shell-friendly projection optimized for Music, Home, and later Search consumption.
- The index is also not a replacement for `Playlist`; playlists remain user-curated groupings of tracks, while the music library index is the canonical per-track library surface.

Minimum per-item shape for the first slice:

- Stable library item identifier
  - Prefer the scoped `NFT.id` as the primary foreign-key anchor for the first slice.
- Scope identity
  - account address
  - chain/network
- Display identity
  - title
  - artist name
  - collection name
- Media pointers
  - canonical audio URL or resolved playback URL
  - artwork/preview image reference
  - content type
- Library state
  - last indexed at
  - source NFT updated-at signal if available
  - availability/status marker for malformed or incomplete local metadata
- Ordering/search support
  - normalized title key
  - normalized artist key
  - normalized collection key

Source vs derived contract:

- Source-of-truth fields remain on `NFT`
  - `id`
  - scoped account/chain identity
  - `name`
  - `artistName`
  - `collectionName`
  - `contentType`
  - `audioUrl`
  - image references
  - any metadata-derived URLs already persisted on the NFT
- Derived index fields are owned by the music library index
  - normalized search/sort keys
  - canonicalized display fallback values when metadata is missing
  - availability flags for missing/bad audio metadata
  - index timestamps
- Persisted-for-relaunch fields in the first slice
  - the index row itself
  - normalized sort/search keys
  - canonical playback pointer chosen for the library view
  - lightweight status flags needed to avoid recomputing all library readiness on every mount

Why this shape is sufficient:

- It is enough to drive a real library list without forcing the UI to re-derive every music-specific concern from raw NFTs on every render.
- It preserves a clean `NFT` foreign-key anchor so `P0-452` can open richer collection/detail screens later without replacing the library foundation.
- It keeps playlist storage separate from library indexing, which avoids mixing \"what exists in the library\" with \"what the user grouped together.\"

Intentional deferrals:

- No collection-detail hierarchy yet; `P0-452` owns that.
- No user curation metadata like favorites, ratings, play counts, or download state in `P0-451`.
- No separate artist or collection tables unless the first slice proves they are necessary.
- No attempt to persist full playback/session state in the library index.
- No requirement that Home or Search consume the full index immediately; they only need a clean seam to attach later.

### 3. Choose and implement the first data source

- [x] Use SwiftData as the storage layer and load from the existing local `NFT` store as the first source.
- [x] Define a deterministic derivation rule from persisted `NFT` records into the music library index.
- [x] Ensure corrupt or partially missing local NFT metadata degrades safely instead of crashing the shell.
- [x] Deduplicate incoming entries in a deterministic way.

First data-source contract:

- Storage layer
  - SwiftData remains the storage layer for both the source `NFT` records and the new music library index rows.
- First source of truth
  - The first library build reads from the existing locally persisted `NFT` store.
- Inclusion rule
  - A source NFT is eligible for the music library index when `nft.isMusic()` is true.
  - In the current codebase that means `audioUrl?.isEmpty == false`.
- Audio-source normalization
  - The metadata pipeline already normalizes `audioUrl`, `audioURI`, `audio`, and `losslessAudio` into `NFT.audioUrl`.
  - The index builder should trust `NFT.audioUrl` as the normalized audio-source field rather than re-parsing raw metadata keys.
- Scope rule
  - Library rows are derived per scoped NFT, preserving account and chain identity from the persisted NFT row.

Deterministic derivation rule:

- Read persisted `NFT` rows for the active scope.
- Filter to rows where `nft.isMusic()` is true.
- Derive one library index row per scoped `NFT.id`.
- Populate display and media fields from the already persisted NFT properties.
- Build normalized sort/search keys from title, artist, and collection values.
- Prefer `nft.musicURL` / canonicalized `audioUrl` semantics for the playback pointer field.
- Use stable fallback values when optional metadata is missing:
  - title fallback: `name` if present, otherwise a deterministic unknown-track label
  - artist fallback: empty or explicit unknown-artist display value chosen once in the index contract
  - collection fallback: empty or unknown-collection display value chosen once in the index contract

Malformed metadata handling:

- If an NFT claims music eligibility through `audioUrl` but URL canonicalization fails, the shell must not crash.
- The index row should still be derivable with an availability/status marker that explains playback is unavailable.
- Missing `artistName`, `collectionName`, artwork, or `contentType` must not exclude an otherwise valid music item.
- The builder must not reach back into raw metadata dictionaries at index time; it should rely on the persisted normalized NFT fields so malformed upstream payloads have already been flattened into a controlled local shape.

Deduplication rule:

- The first dedupe key is the scoped `NFT.id`.
- If multiple source rows somehow collapse to the same music library item during a rebuild, keep the newest deterministic winner and emit at most one index row for that key.
- Do not dedupe by title or artist alone; two different music NFTs can legitimately share those values.

### 4. Implement persistence and refresh behavior

- [x] Persist the music index locally.
- [x] Make relaunch behavior explicit: either restore the stored index or rebuild deterministically and persist again.
- [x] Add a refresh/update path for rebuilding or updating the index.
- [x] Emit refresh/index receipts through the shared receipt foundation.

Persistence contract:

- The music library index is persisted as SwiftData rows, not recomputed as a purely in-memory adapter on every screen mount.
- Each persisted index row must keep a stable foreign-key anchor back to the source scoped `NFT.id`.
- Rebuild behavior should be idempotent for a given scoped NFT set: running the same derivation twice should converge to the same stored index state.
- The persistence layer must support:
  - insert for new music-capable NFTs
  - update for changed derived fields on existing indexed items
  - delete for index rows whose source NFT is no longer present or no longer qualifies as music for the active scope

Relaunch behavior:

- On relaunch, the app should mount from persisted music index rows first when they are available.
- A deterministic rebuild pass may still run afterward or on demand to reconcile the index with the current local `NFT` store.
- The contract should be explicit that the index is a persisted projection of local `NFT` truth, not an independent canonical dataset.

Refresh/update behavior:

- `P0-451` needs a dedicated rebuild/update path that scans the local scoped `NFT` store and reconciles the music library index.
- That rebuild path should be safe to call:
  - after NFT refresh persistence completes
  - on explicit music-library refresh
  - on first mount if the index is missing for the active scope
- Rebuild semantics should be:
  - gather eligible source NFTs
  - derive deterministic library rows
  - upsert changed/new rows
  - remove stale rows for the active scope
  - persist the reconciled index in one controlled save path where practical

Receipt contract:

- Reuse the shared append-only receipt foundation instead of introducing a music-specific logging system.
- Follow the same shape used by the existing refresh recorders:
  - explicit trigger
  - explicit scope
  - summary
  - provenance
  - success/failure
  - correlation ID
  - sanitized payload details
- The first music-library receipt set should cover at least:
  - library index rebuild started
  - library index rebuild completed
  - library index rebuild failed
- Suggested trigger family:
  - `music.library_index.started`
  - `music.library_index.completed`
  - `music.library_index.failed`
- Suggested scope/provenance baseline:
  - scope: `music.library`
  - provenance: `local_cache`
- Payload should include, at minimum:
  - account address
  - chain
  - source NFT count scanned
  - index row count written
  - stale row count removed when relevant
  - error description on failure

Failure and save behavior:

- Partial persistence failure must not leave the shell unusable.
- If rebuild persistence fails, the previously stored index should remain readable when possible.
- Failure receipts should be emitted even when the rebuild does not complete successfully.

### 5. Wire the first consumer surfaces

- [x] Make the index consumable by the active Music surface.
- [x] Expose the index through a clean seam that Home and Search can attach to later without re-plumbing storage ownership.
- [x] If Home/Search hookup is included in the initial slice, keep it lightweight and avoid forcing unfinished surface design into this ticket.
- [x] Keep the shell usable when the library is empty.

Consumer-surface contract:

- The active Music surface is the primary consumer of the new music library index.
- Home and Search are included in the initial slice, but they do not need to be forced onto the dedicated index model immediately if that adds unnecessary surface churn.

Initial attachment rule:

- Music
  - The mounted Music library should move toward consuming the dedicated music library index directly.
- Home
  - Home may attach through a scoped `@Query<[NFT]>` and music filtering for its initial music-aware affordances.
- Search
  - Search may attach through a scoped `@Query<[NFT]>` and music-aware local matching for the initial slice.

Why this is acceptable in the first slice:

- Home and Search already operate as local-shell consumers of persisted data.
- They do not need the full dedicated music-library model to benefit from the fact that music-capable NFTs are locally present.
- This keeps `P0-451` focused on establishing the music foundation without forcing immediate cross-surface rewiring everywhere.

Boundary rule:

- The dedicated music library index is still the long-term music-library contract.
- Allowing Home and Search to use scoped `@Query<[NFT]>` in the initial slice does not mean the app should spread ad hoc music filtering everywhere.
- If Home/Search need richer music-specific metadata later, they should attach through the formal music-library surface rather than duplicating derivation logic.

Empty-state rule:

- Music, Home, and Search must all remain usable when there are zero music-capable NFTs in the local store.
- Empty music data should result in honest empty or no-match states, not shell errors or broken navigation.

### 6. Cover required edge cases

- [ ] Empty dataset shows an honest usable empty state.
- [ ] Duplicate entries do not produce unstable or duplicated visible rows.
- [ ] Partial or malformed local NFT metadata does not crash the shell.
- [ ] Partial persistence failure degrades safely and leaves the shell usable.

### 7. Validate the vertical slice

- [ ] Load the library from the chosen source.
- [ ] Verify local persistence across relaunch if persistence is part of the slice.
- [ ] Verify receipts are emitted on refresh/index actions.
- [ ] Verify the library can still mount with zero items.
- [ ] Record any remaining blockers or intentional deferrals in the session handoff.

## Critical Edge Case

Support empty datasets, duplicate items, and partial or malformed local NFT metadata without crashing or losing a usable shell.

## Explicit Non-Goals

- Do not turn `P0-451` into `P0-452` collection/detail work.
- Do not block on deeper context integration that the dependency note explicitly allows us to defer.
- Do not build throwaway storage shapes that will obviously need replacement in the next Music ticket.

## Validation

Load the library, persist local state across relaunch if needed, and emit receipts on refresh.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.

## Open Questions

- None at the moment. The first source-of-truth choice is now fixed: use SwiftData-backed local `NFT` records and derive the music library index from the existing local store instead of inventing demo or file-backed seed data.
