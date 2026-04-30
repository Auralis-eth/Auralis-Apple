# AuraPlay Phase 2 Implementation Plan

Phase 2 is no longer best represented as a wave-by-wave execution checklist.

The persistence work has now been translated into the retained follow-on docs below so the next engineer does not need to reread stale execution scaffolding to understand what shipped, what remains intentionally deferred, and how to start Phase 3 safely.

## Retained AuraPlay Docs

1. `AuraPlay-Future-Work.md`
   The backlog of incomplete and intentionally deferred work after the Phase 2 persistence slice.
2. `AuraPlay-Physical-Device-QA-Suite.md`
   The real-device manual QA pass for the persisted-library seam, playback lifecycle, and scope-safety checks.
3. `AuraPlay-UI-Design-Audit-Checklist.md`
   The product and interaction audit checklist for the active Phase 2 persistence surface and the remaining migration UI.
4. `AuraPlay-Phase3-Handoff.md`
   The practical handoff notes for starting the next AuraPlay feature phase on top of the shipped persistence seam.
5. `AuraPlay-LLM-Context.md`
   The compact memory layer for future LLM sessions that need the current AuraPlay architecture and deferred-work map fast.
6. `docs/decisions/ADR-002-swiftdata-architecture.md`
   The architecture decision record for the SwiftData container, schema, model actor, and search-boundary choices.

## What Phase 2 Established

- AuraPlay now has a real SwiftData persistence spine under the Phase 1 service seams.
- `AppModelContainer.make(inMemory:)` is the single AuraPlay container factory.
- `AuraPlaySchemaV1` and `AuraPlayMigrationPlan` define the first AuraPlay persistence contract.
- `AuraPlayWallet`, `AuraPlayNFTToken`, and `AuraPlayMediaItem` are now the core persisted AuraPlay graph.
- `AuraPlayWalletService`, `AuraPlayNFTTokenService`, and `AuraPlayMediaItemService` now own background mutation/query work as `@ModelActor` services.
- `ModelContainer` now enters through `AuraPlayDependencies` instead of free-floating global access.
- `LiveAuraPlayLibrarySyncService` now mirrors wallet-scoped music NFTs from the app store into the AuraPlay store.
- `LiveAuraPlayLibraryRepository` now prefers persisted AuraPlay media when a scoped wallet exists and falls back to the legacy indexer when it does not.
- `AuraPlayRootModel` now refreshes through the sync seam before reading the library summary.
- Focused test coverage now exists for schema registration, in-memory container boot, wallet upserts, and persisted-library preference.

## What Phase 2 Deliberately Did Not Finish

- three-tier AuraPlay search
- playlists and ordered playlist-item persistence
- playback history and durable playback state
- deterministic seeding and integration scenarios
- a fully migrated Library, collection/detail, and Now Playing presentation stack

Those are retained as later-phase work, not silent blockers for the shipped Phase 2 slice.

## What This File Is Not Anymore

- not a source of truth for wave-by-wave status
- not the best place to start if you need next-phase execution order
- not the retained home for deferred search, playlist, or playback-state design detail

For implementation detail and next steps, start with:

- `docs/decisions/ADR-002-swiftdata-architecture.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-Future-Work.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-Phase3-Handoff.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-LLM-Context.md`
