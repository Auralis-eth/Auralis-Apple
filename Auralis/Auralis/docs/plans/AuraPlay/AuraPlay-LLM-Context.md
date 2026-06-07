# AuraPlay LLM Context

This is the compact memory layer for future sessions that need the AuraPlay mental model without rereading the whole repo.

## What AuraPlay Is

AuraPlay is the rebuild path for the Auralis Music tab.

It is not:

- a second standalone app
- a second shell
- a TCA experiment
- a greenfield rewrite that gets to ignore the existing `AI/V1` path

## Current Status

- Phase 1 established the module boundary and core architecture seams.
- Phase 2 added the persistence spine underneath those seams.
- Phase 3 added module-owned storage resolution underneath media/artwork URL preparation.
- The Music tab is composed from `MainTabView` into `MusicFeatureRootView`.
- The active AuraPlay root is the Phase 2/3 migration seam, not the final Library/Now Playing product.
- `AuraPlayModelContainer` and the flat `AuraPlaySchema` are live.
- `EOAccount` is the shared persisted account/wallet record; its AuraPlay sync metadata lives in `auraPlaySyncStateRawValue`.
- `AuraPlayMediaItem` is the only AuraPlay-owned persisted music model today.
- `LiveAuraPlayLibrarySyncService` mirrors wallet-scoped music NFTs from the app store into the AuraPlay store.
- `LiveAuraPlayLibraryRepository` prefers persisted AuraPlay media when a scoped wallet exists and falls back to the legacy indexer otherwise.
- Phase 3 storage resolution is implemented in `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`, injected through `AuraPlayDependencies`, and used by `AuraPlayRootModel` for current-track artwork URL preparation.
- Phase 3 ship validation on June 7, 2026 passed the storage-resolution ship test, `StorageResolutionTests`, full `MusicFeatureTests`, the app `Auralis-Full` plan, and the full Xcode build.
- The AuraPlay root still is not the full migrated music product.
- The legacy implementation still lives under `Auralis/MusicApp/AI/V1/`.

## Architecture In One Pass

- shell state remains owned by `ShellStore`, `MainAuraView`, and `AppRouter`
- AuraPlay owns music-module composition and presentation state only
- `MusicAssembly` wires live dependencies into the module
- `AuraPlayRootModel` is the first `@Observable` presentation model
- SwiftData persistence now sits below those seams instead of beside them
- playback state still originates from the shared `AudioEngine`, but AuraPlay talks to it through injected seams

## Key AuraPlay Seams

- `AuraPlayLibraryRepository`
  prefers the persisted AuraPlay media graph and falls back to the legacy music-library index when needed
- `AuraPlayLibrarySyncing`
  mirrors wallet-scoped music NFTs from the app store into the AuraPlay persistence graph
- `AuraPlayPlaybackControlling`
  wraps playback state and control over `AudioEngine`
- `AuraPlayQueueCoordinating`
  currently exposes lightweight queue snapshots
- `AuraPlayArtworkLoading`
  resolves artwork URLs for playback-facing presentation
- `AuraPlayLogging`
  centralizes music-specific logs under categories like `music.library` and `music.playback`
- `AuraPlayModuleConfiguration`
  snapshots the app-level bundle contract AuraPlay depends on
- `AuraPlayError`
  is the current music-domain error surface
- `AuraPlayModelContainer`
  is the only shared AuraPlay SwiftData container factory
- `URLResolver` + `URIScheme` + `GatewayFallbackChain` + `AuraPlayStorageResolutionConfiguration`
  the module-owned storage-resolution stack under `Services/StorageResolution/`; `URLResolver` is wired through `AuraPlayDependencies`, `GatewayFallbackChain` sits above it for HEAD-probed gateway fallback, and `AuraPlayError.mediaResolution(String)` carries failures

## Important Files

- `Auralis/Auralis/Aura/MainTabView.swift`
- `Auralis/Auralis/Assemblies/MusicAssembly.swift`
- `MusicFeature/Sources/MusicFeature/App/MusicFeatureRootView.swift`
- `MusicFeature/Sources/MusicFeature/App/AuraPlayDependencies.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Root/AuraPlayEntryView.swift`
- `MusicFeature/Sources/MusicFeature/Persistence/`
- `MusicFeature/Sources/MusicFeature/Services/`
- `Auralis/docs/plans/AuraPlay/phase3-tickets.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-Phase5-Handoff.md`
- `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`
- `Auralis/MusicApp/AI/Audio Engine/AudioEngine.swift`
- `Auralis/MusicApp/AI/Audio Engine/MusicLibraryIndex.swift`

## Product Decisions That Should Be Treated As Locked

- AuraPlay stays inside the Auralis project
- AuraPlay shares code with the rest of Auralis when that reduces duplication
- the architecture is native SwiftUI plus `@Observable`
- dependencies should be explicit and initializer-injected
- the shell remains the owner of routing and account scope
- migration should be incremental, not all-at-once

## What Is Still Incomplete

- the real Library surface has not been fully migrated into AuraPlay presentation code yet
- the Phase 3 storage-resolution stack ships in `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`; the AuraPlay root uses it for current-track artwork URL preparation, but downstream metadata fetch, audio engine, and image-classifier callers still need deliberate migration from legacy `URLConverter` / `URL.toPinataGatewayURL()` helpers
- three-tier AuraPlay search is still deferred
- playlists and ordered playlist-item persistence are still deferred
- playback history and durable playback state are still deferred
- deterministic seeding and integration scenarios are still deferred
- collection and item-detail flows are still migration work
- Now Playing and queue orchestration migration should happen after Library and detail screens
- physical-device playback validation still matters a lot
- the live audio engine remains a dense concrete dependency even though AuraPlay now wraps it

## Safe Next Move

If asked to keep building AuraPlay, start with the Phase 5 Library surface in `AuraPlay-Phase5-Handoff.md`.

Do not start with Now Playing, playlists, or playback persistence unless the request explicitly overrides that sequencing and accepts the added risk.
