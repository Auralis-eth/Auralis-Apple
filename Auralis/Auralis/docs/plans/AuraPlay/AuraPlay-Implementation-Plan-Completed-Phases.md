# AuraPlay Implementation Plan Completed Phases

This file is the condensed record of the AuraPlay phases that are complete enough that they no longer need to live as active execution checklists.

## Retained AuraPlay Docs

1. `AuraPlay-Future-Work.md`
   The backlog of incomplete and intentionally deferred work after the shipped Phase 3 storage-resolution slice.
2. `AuraPlay-Physical-Device-QA-Suite.md`
   The real-device manual QA pass for the rebuilt music stack, persisted-library seam, storage-resolution seam, and playback lifecycle risks.
3. `AuraPlay-UI-Design-Audit-Checklist.md`
   The product and interaction audit checklist for the current AuraPlay surfaces.
4. `AuraPlay-Phase5-Handoff.md`
   The practical handoff notes for starting the next AuraPlay feature phase safely.
5. `AuraPlay-LLM-Context.md`
   The compact memory layer for future sessions that need the AuraPlay mental model fast.
6. `docs/decisions/ADR-001-auraplay-architecture.md`
   The architecture decision record for the Phase 1 module boundary and integration shape.
7. `docs/decisions/ADR-002-swiftdata-architecture.md`
   The architecture decision record for the Phase 2 SwiftData container, schema, model actor, and search-boundary choices.

## Phase 1 Completed Summary

- AuraPlay now lives inside `Auralis` as the rebuild path for the Music tab.
- The module uses native SwiftUI with `@Observable` presentation state and initializer-based dependency injection.
- The Music tab routes through `AuraPlayTabRootView`, which can preserve the legacy `AI/V1` root or switch to the AuraPlay root.
- The first service seams now exist for library, playback, queue, artwork, logging, and bundle configuration concerns.
- Repo-level lint, CI, privacy, and documentation now recognize the AuraPlay module as a first-class surface.

## Phase 2 Completed Summary

- AuraPlay now has a real SwiftData persistence spine under the Phase 1 service seams.
- `AuraPlayModelContainer.make(inMemory:)` is the single AuraPlay container factory.
- `AuraPlaySchema` currently registers a flat v1-style model list, not a formal `VersionedSchema`.
- The shared `EOAccount` model is the wallet/account source of truth and stores AuraPlay sync metadata in `auraPlaySyncStateRawValue`.
- `AuraPlayMediaItem` is the AuraPlay-owned persisted music projection; NFT origin fields are inline on that model.
- `AuraPlayMediaItemService` owns background mutation/query work as an `@ModelActor` service.
- `ModelContainer` now enters through `AuraPlayDependencies` instead of free-floating global access.
- `LiveAuraPlayLibrarySyncService` now mirrors wallet-scoped music NFTs from the app store into the AuraPlay store.
- `LiveAuraPlayLibraryRepository` now prefers persisted AuraPlay media when a scoped wallet exists and falls back to the legacy indexer when it does not.
- `AuraPlayRootModel` now refreshes through the sync seam before reading the library summary.
- Focused test coverage now exists for schema registration, in-memory container boot, sync metadata, and persisted-library preference.

## Phase 3 Completed Summary

- AuraPlay now owns storage resolution under `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`.
- `URIScheme` classifies IPFS, Arweave, HTTP, HTTPS, `data:`, and unknown URI inputs.
- `URLResolver` synchronously resolves supported raw URIs into HTTPS URLs or deterministic temp-file URLs without network access or SwiftData. The only I/O exception is the bounded `data:` temp-file write.
- `AuraPlayStorageResolutionConfiguration` owns the primary and fallback gateway URLs.
- `GatewayFallbackChain` sits above the pure resolver for HEAD-probed primary/fallback gateway selection.
- `AuraPlayError.mediaResolution(String)` is the module error case for storage-resolution failures.
- `AuraPlayDependencies.urlResolver` and `MusicAssembly` live wiring are in place, and the AuraPlay root already uses the resolver for current-track artwork URL preparation.
- June 7, 2026 validation passed `AuralisTests/AuraPlayStorageResolutionShipTests` 3/3, `MusicFeatureTests/StorageResolutionTests` 12/12, full `MusicFeatureTests` 28/28, `AuralisTests` through the `Auralis-Full` plan, and the full Xcode project build.
- The broader local-package sweep found unrelated package test debt. That follow-up lives in `Phase3-Followup-Package-Test-Restoration.md` and does not reopen Phase 3.

## Still Deferred After The Completed Phases

- full downstream migration of metadata, audio, and image-classifier URL callers onto the Phase 3 resolver seam
- a fully migrated Library, collection/detail, and Now Playing presentation stack
- three-tier AuraPlay search
- playlists and ordered playlist-item persistence
- playback history and durable playback state
- deterministic seeding and integration scenarios
- final legacy `AI/V1` removal

## What These Completed-Phase Docs Are Not

- not a live backlog tracker
- not the source of truth for future phase sequencing
- not the best place to start if you need current implementation detail or the next safe move

For that, start with:

- `Auralis/docs/plans/AuraPlay/AuraPlay-Future-Work.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-Phase5-Handoff.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-LLM-Context.md`
