## AuraPlay Legacy Music Removal Runbook

### Goal

Delete every remaining music implementation that is not `AuraPlay`, with no runtime fallback back into the old experience.

This document is intentionally strict about one thing: in the current repo, "old music" is not only `Auralis/Auralis/MusicApp/AI/V1/`. The remaining `Auralis/Auralis/MusicApp/AI/Audio Engine/` surface should be treated as a compilation scaffold only: empty objects, functions, and properties that still exist so the app builds while AuraPlay finishes replacing legacy references. Several shell routes, schema models, tests, and docs still point at those legacy music types, so deleting the old experience cleanly requires removing those references first or replacing them inside AuraPlay.

### What Is Already True

- There is no active `MusicApp/OLD/` folder to delete. That older ghost path was already cleaned up.
- The remaining legacy music stack is split across:
  - `Auralis/Auralis/MusicApp/AI/V1/`
  - `Auralis/Auralis/MusicApp/AI/Audio Engine/Playlist/`
  - shared AI-era types still used by AuraPlay:
    - `Auralis/Auralis/MusicApp/AI/Audio Engine/AudioEngine.swift`
    - `Auralis/Auralis/MusicApp/AI/Audio Engine/MusicLibraryIndex.swift`

### Current Hot-Path Legacy Dependencies

These are the live seams that prevent an immediate "delete the folder" operation.

#### 1. The Music tab still has a legacy fallback switch

`Auralis/Auralis/MusicApp/AuraPlay/App/AuraPlayTabRootView.swift`

- `AuraPlayTabRootView` switches between:
  - `.legacy` -> `NFTMusicPlayerApp`
  - `.phase2Persistence` -> `AuraPlayCompositionRoot`
- The `.legacy` branch still renders the full old `AI/V1` app.

`Auralis/Auralis/MusicApp/AuraPlay/Core/AuraPlayMigrationStage.swift`

- `AuraPlayMigrationStage` still models a legacy fallback state.
- `resolved(hasAuraPlayPersistence:)` can still route the app back to `.legacy`.

`Auralis/Auralis/Aura/MainTabView.swift`

- The Music tab still passes `auraPlayMigrationStage = .phase2Persistence` into `AuraPlayTabRootView`.

`Auralis/Auralis/Aura/MainAuraView.swift`

- If the AuraPlay store fails to open, the user-facing fallback message still says Music is using the "legacy library path."

#### 2. The Music tab still routes into legacy detail screens

`Auralis/Auralis/Aura/MainTabView.swift`

- `MusicRoute.item` opens `MusicItemDetailView`
- `MusicRoute.collection` opens `MusicCollectionDetailView`

Both of those views live under `Auralis/Auralis/MusicApp/AI/V1/`, so the old detail path is still active even when the tab root is AuraPlay.

#### 3. The app-wide mini player and now-playing stack are still legacy

`Auralis/Auralis/Aura/MainAuraView.swift`

- The bottom accessory still renders `MiniPlayerView(audioEngine:)`

`Auralis/Auralis/MusicApp/AI/V1/MiniPlayerView.swift`

- Presents `NowPlayingView(audioEngine:)`

`Auralis/Auralis/MusicApp/AI/V1/NowPlayingView.swift`

- Uses legacy queue previews and old playback UI.

If the goal is "not a trace left," these must either be rebuilt inside AuraPlay or explicitly removed from the product before deletion.

#### 4. AuraPlay still depends on AI-era playback infrastructure

`Auralis/Auralis/MusicApp/AuraPlay/Services/AuraPlayPlaybackControlling.swift`

- `AuraPlayAudioEnginePlaybackController` adapts `AudioEngine`

`Auralis/Auralis/MusicApp/AuraPlay/Services/AuraPlayQueueCoordinating.swift`

- `AuraPlayAudioEngineQueueCoordinator` reads `audioEngine.nextAudio` and `audioEngine.previousAudio`

`Auralis/Auralis/Aura/MainAuraView.swift`

- The shell still boots `AudioEngine()` and stores it in `@State`

This means `AudioEngine.swift` cannot be deleted until AuraPlay owns playback through a non-legacy type.

#### 5. AuraPlay still depends on the old music-library index layer

`Auralis/Auralis/MusicApp/AuraPlay/App/AuraPlayTabRootView.swift`

- Takes `musicLibraryIndexer: any MusicLibraryIndexing`
- Builds `LiveAuraPlayLibraryRepository` with that indexer

`Auralis/Auralis/MusicApp/AuraPlay/Services/AuraPlayLibraryRepository.swift`

- Falls back to `MusicLibraryIndexing`
- Returns `MusicLibraryIndexRebuildResult`

`Auralis/Auralis/AppServices.swift`

- `MainTabDependencies` still exposes `musicLibraryIndexer`
- `ShellServiceHub` still constructs `SwiftDataMusicLibraryIndexer`

This means `MusicLibraryIndex.swift` cannot be deleted until AuraPlay uses only its own persisted wallet/media graph.

#### 6. AI-era playlist types are still part of the primary data model and audio engine

`Auralis/Auralis/MusicApp/AI/Audio Engine/Playlist/Playlist.swift`

- `Playlist` is a SwiftData model
- `NFT.playlists` points to it
- `AudioEngine` still creates in-memory queue state with:
  - `previousAudio = Playlist(name: "Previous")`
  - `nextAudio = Playlist(name: "Next")`

`Auralis/Auralis/PrimaryStoreSchema.swift`

- Primary schema still includes `Playlist.self`

`Auralis/Auralis/PrivacyResetService.swift`
`Auralis/Auralis/Helpers/SwiftDataNFTCleanup.swift`

- Both still delete `Playlist` and `MusicLibraryItem`

This means the legacy playlist layer cannot be removed safely until queue state is decoupled from `Playlist` and the product decision is made about whether user playlists live in AuraPlay or are being removed entirely.

### Exact Legacy Files To Delete Once Replacements Exist

#### Delete the entire old UI surface

Delete these files after their behavior has been replaced in AuraPlay:

- `Auralis/Auralis/MusicApp/AI/V1/App.swift`
- `Auralis/Auralis/MusicApp/AI/V1/Chain+DisplayName.swift`
- `Auralis/Auralis/MusicApp/AI/V1/DetailRow.swift`
- `Auralis/Auralis/MusicApp/AI/V1/MiniPlayerView.swift`
- `Auralis/Auralis/MusicApp/AI/V1/MusicCollectionCard.swift`
- `Auralis/Auralis/MusicApp/AI/V1/MusicCollectionDetailView.swift`
- `Auralis/Auralis/MusicApp/AI/V1/MusicItemDetailView.swift`
- `Auralis/Auralis/MusicApp/AI/V1/MusicLibraryCard.swift`
- `Auralis/Auralis/MusicApp/AI/V1/NFTMusicPlayerLibraryView.swift`
- `Auralis/Auralis/MusicApp/AI/V1/NowPlayingView.swift`
- `Auralis/Auralis/MusicApp/AI/V1/RecentlyPlayedMiniCard.swift`
- `Auralis/Auralis/MusicApp/AI/V1/RecentlyPlayedSection.swift`
- `Auralis/Auralis/MusicApp/AI/V1/SidebarItem.swift`

#### Delete the legacy playlist surface if playlists are removed or fully re-homed into AuraPlay

- `Auralis/Auralis/MusicApp/AI/Audio Engine/Playlist/NewPlaylistView.swift`
- `Auralis/Auralis/MusicApp/AI/Audio Engine/Playlist/Playlist.swift`
- `Auralis/Auralis/MusicApp/AI/Audio Engine/Playlist/PlaylistCRUD.swift`
- `Auralis/Auralis/MusicApp/AI/Audio Engine/Playlist/PlaylistDeletionService.swift`
- `Auralis/Auralis/MusicApp/AI/Audio Engine/Playlist/PlaylistListView.swift`

#### Delete shared AI-era infrastructure only after AuraPlay replacements land

- `Auralis/Auralis/MusicApp/AI/Audio Engine/AudioEngine.swift`
- `Auralis/Auralis/MusicApp/AI/Audio Engine/MusicLibraryIndex.swift`
- `Auralis/Auralis/MusicApp/AI/Audio Engine/PRIVACY.md`

### Required Code Changes Before Deletion

#### Phase 1. Remove the legacy fallback from the Music tab

Required changes:

- Make `AuraPlayTabRootView` always render AuraPlay.
- Delete `AuraPlayMigrationStage`.
- Remove the `.legacy` branch and all `NFTMusicPlayerApp` wiring.
- Remove the "legacy library path" fallback wording from `MainAuraView`.
- If AuraPlay persistence cannot open, the Music tab must show an explicit unavailable state.
- Do not silently route into `AI/V1`.
- Do not silently fall back into an ephemeral or non-persistent Music mode.
- The unavailable state must define concrete recovery behavior:
  - Always offer a retry action that attempts to open the AuraPlay store again.
  - If the failure is classified as likely-local and not recoverable in-process, show explicit guidance that the user may need to delete and reinstall the app to rebuild local AuraPlay storage.
  - If the app exposes diagnostics or support entry points, link to them from this state.
  - If none of those paths exist yet, say so plainly and treat the state as informational only rather than implying a missing action.
- Disable edits, imports, tagging, organization, playlist mutation, and queue changes that appear durable while persistence is unavailable.
- Report the failure through app diagnostics or receipt-style history if that surface exists.
- A labeled future mode such as `Temporary Session` or `Preview Only` may be explored later, but it is out of scope for this removal plan and must not become the default failure path.

Definition of done:

- No code path in the shipping app can render `NFTMusicPlayerApp`.

#### Phase 2. Replace every legacy route still reachable from AuraPlay

Required changes:

- Replace `MusicItemDetailView` with an AuraPlay-owned detail screen.
- Replace `MusicCollectionDetailView` with an AuraPlay-owned collection screen.
- Move `MusicCollectionSummary` out of `AI/V1` or replace it with an AuraPlay type.
- Update `MainTabView` to navigate only to AuraPlay presentation types.
- Keep all Music tab detail routing inside AuraPlay-owned presentation code. Do not leave mixed routing where the tab root is AuraPlay but push destinations still come from `AI/V1`.

Definition of done:

- `MainTabView` no longer imports or instantiates any type from `MusicApp/AI/V1/`.

#### Phase 3. Replace the legacy mini player and now-playing UI

Required changes:

- Preserve the shell playback UI as a product feature.
- Treat the legacy mini player and now-playing stack as the feature-parity baseline. The AuraPlay-owned replacement must be functionally identical unless a separate product decision explicitly narrows scope.
- Rebuild the shell bottom accessory using AuraPlay-owned UI.
- Replace `MiniPlayerView` and `NowPlayingView` with AuraPlay-owned equivalents.
- Replace `RecentlyPlayedSection` if that concept is still part of the product.

Definition of done:

- `MainAuraView` no longer renders `MiniPlayerView`.
- No shipping UI references `NowPlayingView`.
- The shell bottom accessory path is fully AuraPlay-owned.

#### Phase 4. Empty and remove `MusicApp/AI/Audio Engine/`

Required changes:

- Do not preserve `AudioEngine` as a shared bridge. Replace it with AuraPlay-owned playback and queue state.
- Remove `AuraPlayAudioEnginePlaybackController`.
- Remove `AuraPlayAudioEngineQueueCoordinator`.
- Update shell bootstrapping so `MainAuraView` does not instantiate `AudioEngine` from the legacy folder.
- Make `Auralis/Auralis/MusicApp/AI/Audio Engine/` functionally empty on the way to deletion. It should not remain as a renamed graveyard for active playback code.

Definition of done:

- No AuraPlay service imports `AudioEngine` from `MusicApp/AI/Audio Engine/`.
- `MainAuraView` no longer stores `AudioEngine` state.
- `MusicApp/AI/Audio Engine/` has no active runtime role left.

#### Phase 5. Remove the old library-index bridge

Required changes:

- Make AuraPlay library reads come only from:
  - `AuraPlayWallet`
  - `AuraPlayNFTToken`
  - `AuraPlayMediaItem`
- Remove `MusicLibraryIndexing` from `MainTabDependencies`.
- Remove `musicLibraryIndexerFactory` from `ShellServiceHub`.
- Delete `SwiftDataMusicLibraryIndexer`.
- Delete `MusicLibraryItem`, `MusicLibraryItemDescriptor`, and `MusicLibraryIndexRebuildResult` once nothing depends on them.

Important constraint:

- `LiveAuraPlayLibraryRepository` currently uses the AI-era indexer as a fallback when the AuraPlay graph is not present. That fallback must be removed before `MusicLibraryIndex.swift` can go away.

Definition of done:

- AuraPlay library inventory never reads from `MusicLibraryItem`.

#### Phase 6. Re-home playlists into AuraPlay, then remove the AI-era playlist stack

Required changes:

- Preserve playlists as an AuraPlay product feature.
- Create AuraPlay-native playlist models and services.
- Remove `NFT.playlists` dependency on legacy `Playlist`.
- Update playback queue internals so they do not use `Playlist` as an in-memory queue type.
- Delete `Playlist`, playlist CRUD, playlist delete service, and playlist views from the AI-era folder once AuraPlay-owned replacements exist.
- Remove `Playlist.self` from `PrimaryStoreSchema` once the AuraPlay-native playlist replacement is live.

Non-negotiable prerequisite:

- AuraPlay queue state must be independent of `Playlist(name:)` before `Playlist.swift` can be deleted.

Definition of done:

- `Playlist` is gone from the schema, cleanup services, and audio queue internals.

### Non-File Cleanup Required

#### Update schema and destructive-cleanup code

When `Playlist` and `MusicLibraryItem` are removed:

- Update `Auralis/Auralis/PrimaryStoreSchema.swift`
- Update `Auralis/Auralis/PrivacyResetService.swift`
- Update `Auralis/Auralis/Helpers/SwiftDataNFTCleanup.swift`
- Update `Auralis/Auralis/DataModels/NFT.swift`

#### Update dependency wiring

- Update `Auralis/Auralis/AppServices.swift`
- Update `Auralis/Auralis/Aura/MainAuraView.swift`
- Update `Auralis/Auralis/Aura/MainTabView.swift`
- Update any preview/test bootstrap that still instantiates the old music dependencies

#### Delete or rewrite legacy tests

These tests are tied directly to old music types and must be rewritten against AuraPlay:

- `Auralis/AuralisTests/MusicCollectionPresentationTests.swift`
- `Auralis/AuralisTests/MusicItemDetailPresentationTests.swift`
- `Auralis/AuralisTests/MusicLibraryIndexTests.swift`

These tests must be updated if they still reference removed bridge types:

- `Auralis/AuralisTests/AuraPlayFoundationBoundaryTests.swift`
- `Auralis/AuralisTests/AuraPlayPersistenceWave2Tests.swift`
- `Auralis/AuralisTests/PrivacyResetServiceTests.swift`
- `Auralis/AuralisTests/HelperConsistencyTests.swift`
- `Auralis/AuralisTests/UndoSupportTests.swift`

#### Delete or rewrite documentation references

These docs currently mention the legacy music path and must be corrected:

- `AGENTS.md`
- `Journal.md`
- `Auralis/Auralis/docs/decisions/ADR-001-auraplay-architecture.md`
- `Auralis/Auralis/docs/plans/AuraPlay/AuraPlay-Future-Work.md`
- `Auralis/Auralis/docs/plans/AuraPlay/AuraPlay-LLM-Context.md`
- `Auralis/Auralis/docs/plans/AuraPlay/AuraPlay-Phase3-Handoff.md`
- `Auralis/Auralis/docs/plans/Phase-0-LLM-Handoff.md`
- `Auralis/Auralis/docs/plans/P0-Future-Work.md`
- `Auralis/Auralis/MusicApp/AuraPlay/AuraPlay-README.md`

### Recommended Execution Order

1. Build AuraPlay-native item detail, collection detail, mini player, now-playing, and playlist surfaces.
2. Migrate Music item detail, collection detail, mini player, and now-playing routing to AuraPlay-owned views.
3. Remove legacy routing and fallback logic from `MainTabView`, `MainAuraView`, and `AuraPlayTabRootView`.
4. Empty and remove `MusicApp/AI/Audio Engine/`.
5. Remove the `MusicLibraryIndex` bridge and old `MusicLibraryItem` model.
6. Remove playlist legacy types after AuraPlay-native equivalents are live.
7. Delete `MusicApp/AI/V1/`.
8. Delete the remaining AI-era shared infrastructure and references.
9. Update legacy tests and docs.
10. Build and run the full test suite.

### Acceptance Checklist

The deletion is complete only when all of the following are true:

- No shipped screen renders a type from `Auralis/Auralis/MusicApp/AI/`
- `MusicApp/AI/V1/` is deleted
- `AuraPlayMigrationStage` is deleted
- `NFTMusicPlayerApp` is deleted
- `MiniPlayerView` and `NowPlayingView` are deleted or replaced with AuraPlay-owned types
- `MainTabView` does not instantiate `MusicItemDetailView` or `MusicCollectionDetailView`
- AuraPlay owns Music detail routing and the mini-player path end-to-end
- AuraPlay does not depend on `AudioEngine` from the AI folder
- AuraPlay does not depend on `MusicLibraryIndexing` or `MusicLibraryItem`
- `Playlist` is either removed entirely or re-homed into AuraPlay with no AI-folder ownership left
- `PrimaryStoreSchema` contains no AI-era music models
- privacy reset and account cleanup contain no AI-era music cleanup branches
- all legacy tests are rewritten
- all docs stop describing a legacy fallback path
- `MusicApp/AI/Audio Engine/` is empty or deleted
- project builds cleanly
- tests covering the Music tab pass with only AuraPlay paths in play

### Hard Rule

Do not treat "delete `AI/V1`" as the whole task. That would leave the app compiling against legacy playback, legacy queue types, legacy library indexing, or dead shell routes. The real target is stronger:

`AuraPlay` must be the only music experience left in the repo and the only music path the app can execute.
