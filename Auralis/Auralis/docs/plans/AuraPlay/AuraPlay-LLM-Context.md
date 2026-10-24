# AuraPlay LLM Context

**Last reconciled with code:** 2026-10-22

This is the compact memory layer for future sessions that need the AuraPlay mental model without rereading the whole repo.

## What AuraPlay Is

AuraPlay is the rebuild path for the Auralis Music tab.

It is not:

- a second standalone app
- a second shell
- a TCA experiment
- a greenfield rewrite that gets to ignore the existing shell, account, playlist, and media-library contracts

## Current Status

- Phase 1 established the module boundary and core architecture seams.
- Phase 2 added the persistence spine underneath those seams.
- Phase 3 added module-owned storage resolution underneath media/artwork URL preparation.
- Phase 5 added the NFT discovery and metadata ingestion pipeline in `MusicFeature/Sources/MusicFeature/Discovery/`.
- The Music tab is composed from `MainTabView` into `MusicFeatureRootView`.
- `AuraPlayModelContainer` and the flat `AuraPlaySchema` are live.
- `EOAccount` is the shared persisted account/wallet record; its AuraPlay sync metadata lives in `auraPlaySyncStateRawValue`.
- AuraPlay owns persisted media, NFT-token, embedding, playlist, and playback-position state in the MusicFeature package.
- `NFTSyncCoordinator` is the authoritative writer of `AuraPlayMediaItem` rows from provider discovery; the old `LiveAuraPlayLibrarySyncService` remains a compatibility projection and deliberately does not write AuraPlay media rows.
- `LiveAuraPlayLibraryRepository` reads the scoped AuraPlay persistence graph. Provider discovery is authoritative; it does not silently substitute primary-store inventory when discovery is unavailable.
- Phase 3 storage resolution is implemented in `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`, injected through `AuraPlayDependencies`, and used by AuraPlay media, metadata, artwork, playback, and video URL-preparation paths.
- Phase 3 ship validation on June 7, 2026 passed the storage-resolution ship test, `StorageResolutionTests`, full `MusicFeatureTests`, the app `Auralis-Full` plan, and the full Xcode build.
- Unrelated package ownership work is deferred outside AuraPlay's current reference set and does not reopen completed feature phases.
- Third-party wallet support must stay behind physical-device proof for Rabby, Rainbow, Coinbase Wallet, MetaMask, Phantom, Backpack, Solflare, Privy, and Dynamic.
- The Music tab no longer routes through the old `AI/V1` root, and the app-local hand-built `AudioEngine.swift` is gone.
- The old `MusicApp/AI/Audio Engine/Playlist/` namespace has been removed; app-owned primary-store playlist helpers now live under `Auralis/MusicApp/AuraPlay/Playlist/` while MusicFeature owns the AuraPlay playlist model/service.

## Architecture In One Pass

- shell state remains owned by `ShellStore`, `MainAuraView`, and `AppRouter`
- AuraPlay owns music-module composition and presentation state only
- `MusicAssembly` wires live dependencies into the module
- `AuraPlayRootModel` is the first `@Observable` presentation model
- SwiftData persistence now sits below those seams instead of beside them
- audio playback state originates from `AuraPlayAudioEngine.AudioEngineController`, wrapped by the app-level `AuraPlayPlaybackRuntime` and injected through MusicFeature seams

## Key AuraPlay Seams

- `AuraPlayLibraryRepository`
  reads the persisted, wallet-and-chain-scoped AuraPlay media graph
- `AuraPlayLibrarySyncing`
  is a compatibility projection seam; provider discovery through `NFTSyncCoordinator` owns media writes
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
- `NFTSyncCoordinator`
  the Phase 5 discovery pipeline coordinator: provider discovery, metadata fetch/parse, classification, token/media persistence, inactive reconciliation, indexing, embedding queueing, and artwork prefetch
- `AlchemyNFTClient` + `HeliusNFTClient`
  the live EVM and Solana NFT discovery clients behind provider-neutral DTO contracts

## Important Files

- `Auralis/Auralis/Aura/MainTabView.swift`
- `Auralis/Auralis/Assemblies/MusicAssembly.swift`
- `MusicFeature/Sources/MusicFeature/App/MusicFeatureRootView.swift`
- `MusicFeature/Sources/MusicFeature/App/AuraPlayDependencies.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Root/AuraPlayEntryView.swift`
- `MusicFeature/Sources/MusicFeature/Persistence/`
- `MusicFeature/Sources/MusicFeature/Services/`
- `Auralis/docs/plans/AuraPlay/AuraPlay-Status.md`
- `Auralis/docs/plans/P0-Future-Work.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-Phase14-Known-Limitations.md`
- `MusicFeature/Sources/MusicFeature/Discovery/`
- `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`
- `AuraPlayAudioEngine/Sources/AuraPlayAudioEngine/AudioEngineController.swift`
- `AuraPlayVideoEngine/Sources/AuraPlayVideoEngine/VideoPlayerController.swift`
- `Auralis/MusicApp/AuraPlay/Playlist/` (app-owned primary-store playlist receipt helpers kept out of the old engine namespace)

## Product Decisions That Should Be Treated As Locked

- AuraPlay stays inside the Auralis project
- AuraPlay shares code with the rest of Auralis when that reduces duplication
- the architecture is native SwiftUI plus `@Observable`
- dependencies should be explicit and initializer-injected
- the shell remains the owner of routing and account scope
- migration should be incremental, not all-at-once

## What Is Still Incomplete

- the latest recorded standalone `MusicFeature` run passed 132 tests across 21 suites on 2026-10-21; rerun after relevant code changes
- physical-device playback validation still matters a lot
- third-party wallet support is not production-proven until Rabby, Rainbow, Coinbase Wallet, MetaMask, Phantom, Backpack, Solflare, Privy, and Dynamic each pass the hardware QA matrix
- manual accessibility/App Store release gates remain outside automated proof
- shipping AuraPlay playlists and the legacy primary-store playlist helpers are intentionally separate and must never be synchronized implicitly
- the package audio engine remains a dense concrete dependency even though AuraPlay now wraps it

## Safe Next Move

If asked to keep building AuraPlay, start with `AuraPlay-Status.md`, then use `P0-Future-Work.md`, the known-limitations document, and the QA contracts for remaining work.

Do not treat deleted phase handoff files as source of truth; their still-relevant work has been folded into the living docs.
