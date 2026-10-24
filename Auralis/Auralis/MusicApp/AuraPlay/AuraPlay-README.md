# AuraPlay

AuraPlay is the shipping Music feature inside Auralis, not a standalone app or a second shell.

## Ownership Map

- `MusicFeature/Sources/MusicFeature/`
  Owns the domain values, SwiftData schema and services, discovery, receipts, feature protocols, and primary SwiftUI
  presentation hierarchy.
- `AuraPlayAudioEngine/` and `AuraPlayVideoEngine/`
  Own playback-engine internals.
- `Auralis/MusicApp/AuraPlay/`
  Owns app-specific adapters: playback composition, platform bridges, video hosting, and the separate primary-store
  playlist compatibility helpers.
- `Auralis/Assemblies/MusicAssembly.swift`
  Builds the live dependency graph and injects it into `MusicFeatureRootView`.

Shell routing, account selection, and chain scope remain owned by `ShellStore`, `MainAuraView`, and `AppRouter`.

## Current Production Path

- `MainTabView` presents `MusicFeatureRootView`, whose primary screen is `LibraryRootView`.
- `NFTSyncCoordinator` is the authoritative writer of AuraPlay inventory from wallet/chain provider discovery.
- `AuraPlayModelContainer` owns AuraPlay media, NFT-token, embedding, playlist, ordered playlist-item, and playback
  position state. The schema is currently flat; the pre-release V1-to-V2 migration scaffolding was removed.
- Audio uses `AuraPlayAudioEngine.AudioEngineController` through the app-owned `AuraPlayPlaybackRuntime`.
- Video uses `AuraPlayVideoEngine` through the app-owned video presentation bridge.
- The shipping playlist path is `AuraPlayPlaylistService`, decorated by `ReceiptBackedAuraPlayPlaylistManager`.
- `Playlist/` is a non-shipping compatibility/test path for the primary-store `Playlist` model. It is never silently
  synchronized with AuraPlay playlists and must not be reintroduced into the Music tab.
- Auto-organization is receipt-backed preview only. Applying changes requires a separately reviewed mutation contract.
- Provider metadata is immutable; optional user overrides drive presentation, sorting, semantic text, and Spotlight.

## Sources Of Truth

- `Auralis/docs/plans/AuraPlay/AuraPlay-Status.md` — detailed as-built record and dated automated evidence.
- `Auralis/docs/plans/AuraPlay/AuraPlay-LLM-Context.md` — compact orientation for future work.
- `Auralis/docs/plans/AuraPlay/AuraPlay-Physical-Device-QA-Suite.md` — single manual hardware release gate.
- `Auralis/docs/plans/AuraPlay/AuraPlay-Phase14-Known-Limitations.md` — accepted constraints and release disclosures.
- `Auralis/docs/plans/P0-Future-Work.md` — genuine follow-on backlog.

Completed phase plans, the UI requirements/gaps ledger, the old production-readiness session log, and the Phase 14
master checklist are retired. Do not recreate them as competing sources of truth.
