# AuraPlay Phase 9 Library UI Implementation Plan

## Summary

Phase 9 turns AuraPlay from a migration dashboard into the real Music tab home screen: a wallet-scoped media library with segmented browsing, grid/list modes, collection and creator detail routes, manual playlists, pull-to-refresh sync status, and a persistent mini-player driven by the Phase 8 orchestrator.

This is a full implementation plan for P9-001 through P9-009. It deliberately includes the model, service, adapter, accessibility, and test work hidden under the UI tickets. No ticket should be treated as "UI-only" if its acceptance criteria require missing data contracts.

## Implementation Status — Implemented (with divergences)

**Status: implemented on branch `music-mini-app`.** The "Current Baseline", "Required Foundations", and "Risks And Decisions" sections below describe the *pre-implementation* state and are retained for design rationale. The foundations they list as missing now exist. The production Music tab opens to `LibraryRootView` (`MusicFeatureRootView` composes it; wired at `Auralis/Auralis/Aura/MainTabView.swift`).

As-built confirmations:

- Public playback contract: `AuraPlayPlaybackOrchestrating` exists; mini-player uses `OrchestratorState` visibility.
- Typed query: `MediaItemQuery` (`MediaItemQueryItem`, sort/filter) + `AuraPlayMediaItemService`.
- Schema fields present on `AuraPlayMediaItem`: `durationSeconds`, `lastPlayedAt`, `creatorIdentifierRawValue` (with `#Index`/`#Unique`).
- Grouped index: `GroupedLibraryIndex`. Playlists: `AuraPlayPlaylist`, `AuraPlayPlaylistItem`, `AuraPlayPlaylistService`.
- `swift-snapshot-testing` is a MusicFeature test dependency; P9-009 snapshots live in `LibraryAndPlayerSnapshotTests`.

Divergences from this plan (intentional, not defects):

1. **Naming drift.** Grid and list are not separate `LibraryGridView`/`LibraryListView` types — they are inline `LazyVGrid`/`List` branches in `LibraryRootView`, switched by `LibraryLayoutMode` (`LibrarySegment.swift`) with per-segment `@AppStorage` keys `auraplay.library.layout.{all,audio,video}`. Collection detail is `AuraPlayMusicCollectionDetailView`; there is no separate `CreatorDetailView` — collections and creators both route through the generic `LibraryGroupDetailView` / `LibraryGroupDetailLoaderView`. The shared cell is `LibraryItemCellViewModel` + `LibraryItemCell`. `AddToPlaylistSheet` and `PlaylistNameEditorSheet` live in `LibraryDetailViews.swift`.
2. **Sync/indexing surface consolidated.** The separate `SyncStatusBanner` / `IndexingStatusPill` / `EmbeddingProgress` names were collapsed into one `AuraPlayIndexingStatus` (Equatable, Sendable) value plus its presentation.
3. **No schema versioning/migration.** Because the app has not shipped, the additive schema changes (duration/lastPlayed/creator id, playlist models) were made directly with **no `VersionedSchema`/`SchemaMigrationPlan`**. This closes Risk #1 below by decision: no migration is needed pre-ship.
4. **Snapshot baselines re-recorded.** The originally committed `LibraryAndPlayerSnapshotTests` baselines were bad (dark-text-on-dark, illegible) and are not regressions in current code. They were re-recorded on the local host (Xcode-beta, iOS 27 SDK) and pass deterministically across consecutive runs. Note: the `light` and `dark` variants render identically because the player/library views force their own dark Aura stage regardless of `colorScheme`; the separate variants are redundant and a candidate for cleanup.

## Current Baseline

What exists now:

- `MusicFeatureRootView` composes `AuraPlayEntryView` as the current Music tab root.
- `AuraPlayEntryView` is a useful migration surface, but it is not the Phase 9 Library product screen. It performs client-side filtering over `MusicLibraryItem` and mixes summary, semantic search, collections, tracks, and integration status in one scroll view.
- `AuraPlayMediaItem`, `AuraPlayNFTToken`, `AuraPlayMediaEmbedding`, and `AuraPlayPlaybackPositionState` are in `AuraPlaySchema`.
- `NFTSyncCoordinator` exposes `SyncProgress`, `syncAll()`, and `syncAllIfNeeded()`.
- `AuraPlayEmbeddingService` can process embeddings and perform semantic search, but there is no UI-facing `EmbeddingProgress` pending-count contract yet.
- Phase 8 `PlaybackOrchestrator` exists in the app target, but it is private app implementation. `MusicFeature` currently sees only `AuraPlayPlaybackControlling` and `AuraPlayQueueCoordinating`, which are too thin for Phase 9 mini-player and bounded queue requirements.
- `AuraPlayPlaybackQueue` supports a finite queue but has no lazy extension contract.
- `AuraPlaySchema` has no AuraPlay-owned playlist or ordered playlist-item models.
- Legacy playlist CRUD exists against `AuralisPrimaryPersistence.Playlist` and `NFT`, but that model stores unordered `tracks: [NFT]` and is not the Phase 9 playlist contract.
- The app target already has the Aura design system pattern: scenic stage, `AuraSurfaceCard`, `AuraSectionHeader`, `AuraActionButton`, `AuraPill`, `AuraEmptyState`, semantic text, `AuraMotionPolicy`, and accessibility identifiers in `AuraUI`.

## Non-Negotiable Phase 9 Invariants

- Library UI reads AuraPlay-owned media rows, not legacy `MusicLibraryItem`, once the new query service is available.
- All browsing surfaces share one `LibraryItemCellViewModel` and one cell component family.
- Playback starts from the Phase 8 orchestrator only. There is no second playback state for Library cells or the mini-player.
- Queue start is bounded by default to 100 materialized items. Large libraries must not allocate the full filtered result on tap.
- Lazy queue extension is a pure function of the captured query context: sort, filter, scope, and offset. It must not read live view state after navigation.
- Manual pull-to-refresh calls `syncAll()`, not `syncAllIfNeeded()`.
- Playlist ordering is persisted through service-managed ordered rows, not by trusting array order on the legacy `Playlist.tracks` relationship.
- Accessibility lands with each feature slice, then P9-008 audits and hardens. Do not defer labels, Dynamic Type layout, or Reduce Motion behavior until the end.
- `AuraUI/Sources/AuraUI/A11yID.swift` is updated before any new UI flow lands in tests.

## Required Foundations Before Replacing The Root

These are implementation work, not optional cleanup.

### 1. Promote Phase 8 Playback Read/Control Contracts

Add a public MusicFeature-facing contract that exposes orchestrator-shaped state without exporting app-private engine internals.

Recommended package contract:

- `AuraPlayOrchestratorState`: public, `Equatable`, `Sendable`
  - `.idle`
  - `.loading(AuraPlayPlaybackItemPresentation)`
  - `.playing(AuraPlayPlaybackItemPresentation)`
  - `.paused(AuraPlayPlaybackItemPresentation)`
  - `.buffering(AuraPlayPlaybackItemPresentation)`
  - `.failed(AuraPlayPlaybackItemPresentation, message: String)`
- `AuraPlayPlaybackItemPresentation`: id, title, creator, artworkURLString, duration, mediaKind, isPiPActive.
- `AuraPlayPlaybackOrchestrating`: `@MainActor` protocol exposing `state`, `currentTime`, `togglePlayPause()`, `pause()`, `play(item:queue:startAt:origin:)`, `restoreVideoPresentation()`.
- `AuraPlayQueueWindow`: materialized items, start index, origin, query context, window size, next offset.
- `AuraPlayQueueExtending`: async fetch of the next window from a captured query context.

Live app work:

- Add an adapter from app-private `PlaybackOrchestrator` and `AuraPlayableMediaItem` into the public MusicFeature protocol.
- Keep `PlaybackOrchestrator` itself app-private unless a later architecture pass deliberately moves it into a package.
- Extend `AuraPlayPlaybackRuntime` to expose the adapter and to route existing `playLibraryItem` calls through the same bounded-queue path.
- Add tests that prove the adapter mirrors `.idle`, `.playing`, `.paused`, restored paused, and failure states.

### 2. Add Typed Media Query Surface

Phase 9 depends on typed sort/filter. Implement this before grid/list UI.

Add in `MusicFeature`:

- `MediaItemSort`: `.dateAdded`, `.titleAZ`, `.creatorAZ`, `.duration`, `.lastPlayed`.
- `MediaItemMediaTypeFilter`: `.all`, `.audio`, `.video`.
- `MediaItemFilter`: scope, selected chains, media type, unplayed-only.
- `MediaItemQueryContext`: scope, sort, filter, offset, limit.
- `MediaItemQueryResult`: items plus total count and next offset if available.
- `AuraPlayMediaItemService.fetchSorted(context:)` and `fetchWindow(context:)`.

Schema gaps to close:

- `durationSeconds` is currently present in `MediaItemDTO` but not persisted on `AuraPlayMediaItem`. Add it.
- `lastPlayed` comes from `AuraPlayPlaybackPositionState.lastPlayedAt`. Implement service-level sort support with either a secondary fetch/join in the actor or a denormalized `lastPlayedAt` on `AuraPlayMediaItem` updated by playback persistence. Pick one and test it. For Phase 9, denormalizing `lastPlayedAt` is acceptable if `AuraPlayPlaybackPositionStateService` owns the update.
- `unplayed-only` requires playback state lookup. Implement in the service, not in the view.

### 3. Add Grouped Library Index

Collections and creators need distinct grouping without recomputing on every render.

Add:

- `GroupedLibraryIndex<Group>` as a small cache/coordinator keyed by sync-generation, account, chain, and group kind.
- `LibraryCollectionGroup`: collectionName, contractAddress, chain, itemCount, artwork candidates.
- `LibraryCreatorGroup`: creator identifier, displayName, optional address, itemCount, artwork candidates.

Invalidation:

- Invalidate after `SyncProgress.state` transitions to `.complete`.
- Also invalidate after media override changes if creator/collection overrides land later.

Implementation note:

- SwiftData cannot express the desired `GROUP BY` directly. Fetch scoped playable/media-relevant rows once in a model actor, reduce to distinct groups, cache the result, and count fetch calls in tests.

### 4. Add AuraPlay Playlist Models And Service

Do not build Phase 9 playlist UI on the legacy `Playlist.tracks: [NFT]` relationship.

Add to `AuraPlaySchema`:

- `AuraPlayPlaylist`
  - id, name, coverImageURLString, isSmart, smartQueryData, createdAt, updatedAt.
  - duplicate names allowed.
- `AuraPlayPlaylistItem`
  - id, playlistID or relationship, mediaItemID, position, addedAt.
  - relationship/delete behavior should remove playlist items when the playlist is deleted.
  - enforce membership uniqueness at service level even if SwiftData cannot express the exact compound uniqueness desired.

Add `AuraPlayPlaylistService` as `@ModelActor`:

- create(name:)
- rename(id:name:)
- delete(id:)
- fetchPlaylists()
- fetchItems(playlistID:)
- add(mediaItemID:toPlaylist:)
- remove(mediaItemID:fromPlaylist:)
- reorderItem(playlistID:fromPosition:toPosition:)
- toggle(mediaItemID:playlistID:)
- createAndAdd(name:mediaItemID:)

Service rules:

- Positions are contiguous and zero-based after every add, remove, and reorder.
- Duplicate playlist names succeed, but the UI emits a soft warning.
- Smart playlist creation stays out of scope; `isSmart` and `smartQueryData` exist for Phase 13.

### 5. Add Deterministic Seed Support

P9-009 requires `.standard` seed tier. Add this before writing snapshot/interaction tests.

Add test support for:

- `.minimal`, `.standard`, `.large` seed tiers.
- 500-item and 5000-item performance/queue-window scenarios.
- audio-only, video-only, audio+video, non-playable, no-artwork, cached-artwork, multiple chains, multiple collections, duplicate creator display names, duplicate playlist names, restored playback state.
- stable IDs and dates so snapshots do not drift.

Use existing `AuralisTestSupport` where practical. If the helper becomes broadly useful, create a small test-only AuraPlay seeder under `MusicFeature/Tests/MusicFeatureTests` first; only promote to a package after repeated use justifies it.

## Implementation Sequence

### Slice 1: Contracts, IDs, And Query Infrastructure

Files likely created or changed:

- `MusicFeature/Sources/MusicFeature/App/AuraPlayDependencies.swift`
- `MusicFeature/Sources/MusicFeature/Services/AuraPlayPlaybackControlling.swift`
- new `MusicFeature/Sources/MusicFeature/Services/AuraPlayPlaybackOrchestrating.swift`
- new `MusicFeature/Sources/MusicFeature/Domain/MediaItemQuery.swift`
- `MusicFeature/Sources/MusicFeature/Persistence/AuraPlayMediaItem.swift`
- `MusicFeature/Sources/MusicFeature/Persistence/Services/AuraPlayMediaItemService.swift`
- `MusicFeature/Sources/MusicFeature/Persistence/Services/AuraPlayPlaybackStateService.swift`
- `AuraUI/Sources/AuraUI/A11yID.swift`

Work:

1. Add public media query enums/structs.
2. Persist duration and last-played support needed by sort/filter.
3. Add service fetch methods for exact sort/filter/window behavior.
4. Add public playback-orchestrator presentation contract.
5. Add A11y IDs for Library root, segment picker, layout toggle, sort menu, filter sheet, cells, group rows, playlists, add-to-playlist sheet, sync banner, indexing pill, and mini-player.
6. Add focused unit tests for descriptor/query behavior and playback adapter state mapping.

Gate:

- Query tests prove chain/audio/unplayed filters and all sort cases.
- No UI rewrite begins until this compiles and tests pass.

### Slice 2: Library Root Shell (P9-001)

Replace `AuraPlayEntryView` as the primary root with `LibraryRootView`. Keep reusable parts from `AuraPlayEntryView` only where they fit the new model.

Files likely created:

- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibraryRootView.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibrarySegment.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibraryEmptyStateView.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibraryRoute.swift`

Work:

1. Add `NavigationStack` rooted at the library screen.
2. Add segmented control: All, Audio, Video, Collections, Creators, Playlists.
3. Persist segment selection with `@AppStorage`.
4. Add wallet picker entry point in trailing navigation placement. Initially call an injected `openWalletPicker` closure; wire it to the existing account switcher/sheet path in app composition.
5. Implement the three empty states:
   - no wallet connected
   - wallet connected, sync never completed or currently syncing with no results
   - sync complete, zero playable audio/video media
6. Embed mini-player placeholder at root level but leave final behavior for Slice 6.
7. Add root-level `.refreshable`, calling the manual refresh use case added in Slice 7.
8. Use the Aura design system: scenic or dark Aura stage, `AuraSurfaceCard`, `AuraSectionHeader`, `AuraPill`, `AuraActionButton`, and `AuraEmptyState`.

Gate:

- Snapshot tests for all three empty states.
- Test that segment selection persists through view recreation.
- Cold no-wallet state renders without a transient wrong state.

### Slice 3: Shared Cell View Model And Grid/List Browsing (P9-002)

Files likely created:

- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibraryItemCellViewModel.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibraryItemCell.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibraryGridView.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibraryListView.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibraryBrowseControls.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibraryFilterSheet.swift`

Work:

1. Build `LibraryItemCellViewModel` from `AuraPlayMediaItem` only once.
2. Include display title, creator, collection, artwork URL, chain badge, duration, media type, playability, and current-playing indicator.
3. Grid and list containers use the same view model and actions.
4. Add layout toggle persisted per segment via `@AppStorage` keys like `auraplay.library.layout.audio`.
5. Add sort menu and filter sheet bound to typed `MediaItemSort` and `MediaItemFilter`.
6. Use service-backed window fetches. Avoid client-side filtering for large libraries.
7. Non-playable cells render dimmed with a glyph and explanation; they do not call playback.
8. Playable tap calls orchestrator through bounded queue context: current item plus forward window of 100.
9. Add lazy extender hook to append next windows when queue advance nears tail.
10. Use `CachedAsyncImage` or a small wrapper over `AsyncImage` that benefits from the shared `URLCache` and avoids a visible cache-hit flash.

Gate:

- 500-item sort/filter test updates via service query.
- 5000-item tap test proves bounded queue allocation.
- Lazy extender test appends next window near tail.
- Non-playable tap test proves no playback call.
- Grid/list preference persists independently per segment.

### Slice 4: Collections And Creators (P9-003, P9-004)

Files likely created:

- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibraryCollectionsSegmentView.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/LibraryCreatorsSegmentView.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/CollectionDetailView.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/CreatorDetailView.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/GroupedLibraryIndex.swift`

Work:

1. Add collection list using grouped index, one row per distinct contract/chain collection.
2. Add collection detail route by contractAddress + chain.
3. Header includes artwork or four-item mosaic, name, count, and Play All.
4. Use deterministic play-all order. Choose `normalizedTitleKey`, then `sourceNFTID` and document it in tests.
5. Add creator list using grouped index, grouping by underlying creator identifier, not display name.
6. Add creator detail route and Play All.
7. Reuse shared cell view model/components for all detail grids/lists.
8. Reuse ENS/avatar/blockie infrastructure only through an injected avatar resolver. Do not duplicate ENS resolution logic in the view.

Gate:

- Similar collection names with different contracts do not merge.
- Two creators sharing display name do not merge.
- Group fetch/reduce cache invalidates only after sync complete.
- Detail screens show exactly seeded matching items.

### Slice 5: Playlist Persistence And UI (P9-005)

Files likely created:

- `MusicFeature/Sources/MusicFeature/Persistence/AuraPlayPlaylist.swift`
- `MusicFeature/Sources/MusicFeature/Persistence/AuraPlayPlaylistItem.swift`
- `MusicFeature/Sources/MusicFeature/Persistence/Services/AuraPlayPlaylistService.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/PlaylistsSegmentView.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/PlaylistDetailView.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/AddToPlaylistSheet.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/PlaylistNameEditorSheet.swift`

Work:

1. Add models to schema. This is the moment to introduce versioned schema/migration if the project is ready; otherwise document the additive schema risk and keep test containers green.
2. Implement playlist service with contiguous positions.
3. Add playlist segment sorted by updatedAt descending.
4. Add create sheet with duplicate-name soft warning.
5. Add playlist detail with reorderable `List` using native `.onMove`.
6. Add swipe-to-delete for playlist items.
7. Add reusable `AddToPlaylistSheet` from every media cell context menu.
8. New Playlist from the sheet creates and adds in one flow.
9. Rename/delete actions from both row context menu and detail toolbar call the same service methods.
10. Keep smart playlist rule editing out of scope while preserving schema fields.

Gate:

- Create duplicate name succeeds and warns.
- Add/remove/toggle membership works.
- Reorder calls service with correct positions and persists order.
- Delete playlist updates the segment reactively.
- Full playlist round trip test passes against in-memory SwiftData.

### Slice 6: Mini-Player (P9-006)

Files likely created or changed:

- `MusicFeature/Sources/MusicFeature/Presentation/Playback/AuraPlayMiniPlayerView.swift`
- new `MusicFeature/Sources/MusicFeature/Presentation/Playback/LibraryMiniPlayerView.swift` if replacing in place would create churn
- `Auralis/Auralis/Aura/MainTabView.swift`
- `Auralis/Auralis/MusicApp/AuraPlay/Services/AuraPlayPlaybackRuntime.swift`

Work:

1. Make the mini-player observe `AuraPlayPlaybackOrchestrating.state`.
2. Visible for every state except `.idle`, including restored paused.
3. Use artwork, title, creator, play/pause, and progress from the same position source used by Phase 8 persistence.
4. Tap-to-expand uses a closure for Phase 10 full-player presentation. If the full player is not implemented yet, present the existing now-playing surface as the current expansion target and keep the API Phase-10-ready.
5. Reduce Motion swaps matched-geometry/morphing for opacity crossfade.
6. Swipe-dismiss pauses but does not clear the restored session.
7. PiP active state shows a PiP glyph and restore action; never shows a different audio item while video PiP is active.
8. Keep mini-player mounted at `LibraryRootView` level. Avoid per-segment mount/unmount.

Gate:

- State transition tests: idle hidden; loading/playing/paused/buffering/failed visible.
- Restored paused state visible on cold launch.
- Toggle calls orchestrator and updates in one render pass.
- Progress source is orchestrator/position adapter, not a view-owned timer.
- PiP glyph restore path calls the injected video restoration closure.

### Slice 7: Pull-To-Refresh And Status UI (P9-007)

Files likely created:

- `MusicFeature/Sources/MusicFeature/Presentation/Library/SyncStatusBanner.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Library/IndexingStatusPill.swift`
- new `MusicFeature/Sources/MusicFeature/Discovery/EmbeddingProgress.swift`

Work:

1. Expose a UI-observable sync progress dependency from `AuraPlayDependencies` instead of hiding `NFTSyncCoordinator` behind `AuraPlayNFTDiscoverySyncing` only.
2. Manual refresh calls `syncAll()` and returns when network fetch phase completes.
3. Banner shows live tokens/items/playable counts during syncing.
4. Complete auto-dismisses after about 1.5 seconds.
5. Error shows partial-success framing and remains dismissible.
6. Add `EmbeddingProgress.pendingCount` or equivalent from embedding processing.
7. Show "Indexing your library" pill near search/browse controls while pending count is nonzero.

Gate:

- Mock assertion proves `syncAll()` was called.
- Counts update live.
- Error banner copy is non-blocking.
- Refresh spinner is not tied to background embedding/artwork tasks.
- Indexing pill disappears at zero pending.

### Slice 8: Accessibility Hardening (P9-008)

This starts in Slice 1 and finishes here.

Work:

1. Audit every Library screen with Accessibility Inspector.
2. Ensure every icon-only button has a label and input labels where useful.
3. Ensure media cells are one coherent accessibility element with title, creator, media type, playability, collection, and progress/playing state.
4. Segment accessibility labels announce `Library, All, tab 1 of 6` style values.
5. Ensure XXXL Dynamic Type stacks grid/list rows and mini-player without truncation or overlap.
6. Ensure Reduce Motion gates matched geometry and spring animations.
7. Ensure Reduce Transparency/increased contrast fall back to opaque surfaces through `AuraSurfaceCard` or explicit background fallback.
8. Ensure color-only states also have icon/text.
9. Add heading structure and rotor-friendly section headers.
10. Add large content viewer support for compact icon controls.

Gate:

- Zero missing-label warnings across Library screens.
- Snapshot coverage at standard and accessibility text sizes.
- Manual contrast check for text-over-glass surfaces.
- Mini-player transition crossfades under Reduce Motion.

### Slice 9: Integration And Snapshot Tests (P9-009)

Files likely created:

- `MusicFeature/Tests/MusicFeatureTests/LibraryRootViewTests.swift`
- `MusicFeature/Tests/MusicFeatureTests/LibraryBrowsingTests.swift`
- `MusicFeature/Tests/MusicFeatureTests/LibraryGroupingTests.swift`
- `MusicFeature/Tests/MusicFeatureTests/PlaylistServiceTests.swift`
- `MusicFeature/Tests/MusicFeatureTests/PlaylistUITests.swift`
- `MusicFeature/Tests/MusicFeatureTests/MiniPlayerTests.swift`
- `MusicFeature/Tests/MusicFeatureTests/AuraPlayLibrarySeed.swift`

Work:

1. Snapshot empty states, grid, list, light/dark, standard and XXLarge/XXXL Dynamic Type.
2. Interaction test playable and non-playable cell taps.
3. Sort/filter tests against seeded store.
4. Bounded queue and lazy extension tests.
5. Collection/creator detail and grouping tests.
6. Playlist full round trip.
7. Mini-player state visibility including restored paused.
8. Run the full Phase 9 suite repeatedly before closing.

Gate:

- All P9 tests pass.
- Phase 9 suite target runtime under 10 seconds for normal seeded tests. The 5000-item bounded-window case can be isolated if it threatens the budget.
- Snapshot tests pass across 5 consecutive local/CI runs with no drift.

## Ticket Mapping

| Ticket | Implementation Slices | Close Criteria |
|---|---:|---|
| P9-001 Library shell | 1, 2, 6, 7, 8, 9 | Segments, wallet entry, empty states, persistent mini-player mount, root refresh, snapshots. |
| P9-002 Grid/list browsing | 1, 3, 8, 9 | Shared cell VM, service-backed sort/filter, bounded queue, cache-hit artwork, layout persistence. |
| P9-003 Collection detail | 4, 8, 9 | Distinct collection grouping cache, detail screen, Play All deterministic order. |
| P9-004 Creator detail | 4, 8, 9 | Creator grouping by identifier, detail screen, avatar resolver reuse. |
| P9-005 Playlist UI | 5, 8, 9 | AuraPlay playlist models/service/UI, add-to-playlist sheet, reorder/delete/create flows. |
| P9-006 Mini-player | 1, 6, 8, 9 | Orchestrator-state visibility, progress source, PiP awareness, pause-on-dismiss, expand hook. |
| P9-007 Refresh/status | 7, 8, 9 | Manual `syncAll()`, live progress banner, partial-success error, indexing pill. |
| P9-008 Accessibility | all slices, final audit | Inspector clean, Dynamic Type snapshots, Reduce Motion fallback, contrast pass. |
| P9-009 Tests | all slices | Snapshot and interaction gate passes against `.standard` seed tier. |

## Design System Direction

Use the established Auralis pattern:

- Root stage: scenic or dark Aura surface consistent with Gateway, Home, Gas, Search, and Receipts.
- Cards: `AuraSurfaceCard` with `.soft` for grouped panels and `.regular` for prominent cells or empty states.
- Headers: `AuraSectionHeader` with optional `AuraPill` trailing status.
- Actions: `AuraActionButton` for prominent text+icon commands; icon-only actions use `SystemImage` inside native `Button` with labels.
- Status: `AuraPill`, `AuraErrorBanner`, and `AuraEmptyState` for lightweight feedback.
- Motion: use `AuraMotionPolicy` from `@Environment(\.accessibilityReduceMotion)`.
- Accessibility IDs: use `A11yID.AuraPlay` helpers, not raw string literals in new flows.

Liquid Glass note:

- The package targets iOS/macOS 26, and `AuraSurfaceCard` already uses `glassEffect` with Reduce Transparency and increased contrast fallback. Prefer extending `AuraUI` primitives over adding one-off glass effects in Library views.

## Routing And Composition

App shell changes:

- Keep `MainTabView` as the owner of Music navigation stack and route pushes.
- Let `LibraryRootView` emit typed library routes upward or bind to a package-local `NavigationPath` only if routes do not need global shell awareness.
- Detail routes that should be reachable from Search or external navigation should remain in `AppRouter`.
- Wallet picker entry should bridge to the existing account switcher/shell account selection path. Avoid building a second wallet picker in MusicFeature.

Package changes:

- `MusicFeatureRootView` should become a thin composition wrapper over `LibraryRootView`.
- `AuraPlayEntryView` can be retained temporarily as a debug/migration view only if it is removed from the production Music tab route. If retained, it should not be the default user path.

## Validation Plan

Fast during development:

- `XcodeRefreshCodeIssuesInFile` on modified Swift files.
- Focused `RunSomeTests` for new service tests when available.
- `RenderPreview` for key SwiftUI previews once Library views exist.

Phase gates:

1. Build after Slice 1 because schema/protocol changes are high blast radius.
2. Build after Slice 3 because grid/list browsing touches root composition and playback starts.
3. Run playlist service tests before any playlist UI tests.
4. Build after Slice 6 because mini-player touches app/runtime/package seams.
5. Full `BuildProject` and full relevant tests before closing Phase 9.

Manual QA required:

- Wallet missing, sync in progress, zero playable results.
- 500+ item scroll performance on device.
- Pull refresh while already syncing.
- Start playback from grid, list, collection, creator, playlist.
- Restore paused session after cold app launch.
- Video PiP active with mini-player visible and restore action.
- Dynamic Type XXXL and Reduce Motion / Reduce Transparency.

## Risks And Decisions To Make Early

1. Schema migration posture

Adding `durationSeconds`, `lastPlayedAt`, playlists, and playlist items changes the AuraPlay store. Decide whether Phase 9 introduces `VersionedSchema` and migration plan. The existing gaps file already calls this out; Phase 9 is likely the right time.

2. Orchestrator package boundary

The orchestrator is app-private today. Phase 9 should not expose app internals casually. Prefer a public presentation/control protocol and adapter first. Move the orchestrator to a package only if tests and reuse prove the boundary is wrong.

3. Last Played sorting

Either join against playback state in service fetches or denormalize `lastPlayedAt` onto media items. The UI must not compute this by walking arrays.

4. Creator identity

Current media rows have `artistName` but not a durable creator address. To meet the collision acceptance criterion, Phase 9 may need `creatorIdentifierRawValue` on `AuraPlayMediaItem` populated by classifier/provider metadata. If metadata cannot provide it for every chain, use a deterministic fallback that does not merge different raw addresses.

5. Snapshot dependency

The plan references `swift-snapshot-testing`, but it is not currently listed in `MusicFeature/Package.swift`. Either add it deliberately for package tests or implement snapshots through the project’s existing UI snapshot harness if one exists. Do not fake P9-009 with only unit tests.

6. Search reuse

Phase 11 will reuse cell components. Keep `LibraryItemCellViewModel` and cell actions in a neutral `Presentation/Library/Components` area so Search can import them without pulling root-only state.

## Done Definition

Phase 9 is complete only when:

- The production Music tab opens to the new Library root.
- All six segments work against seeded and real local AuraPlay data.
- Grid/list, collection, creator, playlist, and future search surfaces share one item cell model.
- Playback starts through the Phase 8 orchestrator with bounded queue windows and lazy extension.
- Mini-player is persistent, restored-session aware, and PiP aware.
- Manual refresh and sync/indexing status are visible and non-blocking.
- Accessibility audit criteria are met.
- P9-009 snapshot and interaction tests pass against `.standard` seed tier.
- `AuraPlay-Status.md`, `AuraPlay-Gaps.md`, and `Journal.md` are updated to reflect the new reality and any deferred decisions.
