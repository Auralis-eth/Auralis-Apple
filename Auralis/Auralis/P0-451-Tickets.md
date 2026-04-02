# P0-451 Tickets And Session Handoff

## Summary

Implement a minimal music library index with local persistence and refresh receipts, deriving the first library from the existing SwiftData-backed local `NFT` store for Phase 0.

## Ticket Status

Ready for implementation.

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

- [ ] Define the minimum stored/indexed shape needed for a usable Phase 0 music library.
- [ ] Keep the model broad enough that `P0-452` can add collection/detail behavior without forcing a storage rewrite.
- [ ] Decide what is source data, what is derived index data, and what must persist locally across relaunch.
- [ ] Document any intentionally deferred fields so they do not quietly leak into this ticket.

### 3. Choose and implement the first data source

- [ ] Use SwiftData as the storage layer and load from the existing local `NFT` store as the first source.
- [ ] Define a deterministic derivation rule from persisted `NFT` records into the music library index.
- [ ] Ensure corrupt or partially missing local NFT metadata degrades safely instead of crashing the shell.
- [ ] Deduplicate incoming entries in a deterministic way.

### 4. Implement persistence and refresh behavior

- [ ] Persist the music index locally.
- [ ] Make relaunch behavior explicit: either restore the stored index or rebuild deterministically and persist again.
- [ ] Add a refresh/update path for rebuilding or updating the index.
- [ ] Emit refresh/index receipts through the shared receipt foundation.

### 5. Wire the first consumer surfaces

- [ ] Make the index consumable by the active Music surface.
- [ ] Expose the index through a clean seam that Home and Search can attach to later without re-plumbing storage ownership.
- [ ] If Home/Search hookup is included in the initial slice, keep it lightweight and avoid forcing unfinished surface design into this ticket.
- [ ] Keep the shell usable when the library is empty.

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
