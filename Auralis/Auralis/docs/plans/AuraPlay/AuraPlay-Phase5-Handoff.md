# AuraPlay Phase 3 To Phase 5 Handoff

This file hands the next engineer from the completed Phase 3 storage-resolution seam into Phase 5 integration work.

## Completion Answer

Phase 3 is complete enough to close.

Everything in `phase3-tickets.md` has been addressed in the codebase:

- `AuraPlayStorageResolutionConfiguration` exists in `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`.
- `URIScheme` classifies IPFS, Arweave, HTTP, HTTPS, `data:`, and unknown URI inputs.
- `URLResolver` synchronously resolves supported storage strings without network access or SwiftData, with the documented bounded `data:` temp-file exception.
- `GatewayFallbackChain` exists above the resolver for HEAD-probed primary/fallback gateway selection.
- `AuraPlayError.mediaResolution(String)` carries storage-resolution failures through the module error surface.
- `AuraPlayDependencies.urlResolver` and `MusicAssembly` live wiring are in place.
- Focused storage-resolution tests and the app-level ship test exist.

The important caveat: Phase 3 built the seam, but downstream media callers have not all moved onto it. That caller migration is not a Phase 3 gap. It belongs to the downstream phase that consumes the resolver, starting with Phase 5.

## Phase 3 Validation Snapshot

Recorded validation from June 7, 2026:

- `AuralisTests/AuraPlayStorageResolutionShipTests` passed, 3/3.
- `MusicFeatureTests/StorageResolutionTests` passed, 12/12.
- Full `MusicFeatureTests` passed, 28/28.
- `AuralisTests` through the Auralis-Full plan passed.
- The full Xcode project build succeeded.

The broader package sweep found unrelated test debt in other packages. That is tracked separately in `Phase3-Followup-Package-Test-Restoration.md` and should not reopen Phase 3 storage-resolution work.

## What Phase 5 Should Own

Phase 5 should consume the Phase 3 seam from real product paths instead of expanding the resolver itself.

Primary Phase 5 objective:

- Move the first user-facing AuraPlay browse surface onto the persisted AuraPlay graph, then route media/artwork URL normalization through the module-owned resolver where that surface needs storage URLs.

Recommended Phase 5 scope:

1. Build or complete the AuraPlay Library surface under the AuraPlay presentation stack.
2. Keep reads backed by `AuraPlayLibraryRepository`, which already prefers the persisted graph for a scoped wallet.
3. Use `URLResolver` for synchronous normalization of stored media/artwork URLs at the presentation or service boundary that owns URL preparation.
4. Use `GatewayFallbackChain` only for paths that actually need network reachability probing before handing a URL to a fetcher or loader.
5. Leave Now Playing, deep queue orchestration, playlists, and durable playback history out of Phase 5 unless the phase charter explicitly expands.

The reason for this order is simple: Library is read-heavy, scope-sensitive, and visible. It proves the persistence and resolver seams without forcing playback lifecycle risk into the same slice.

## Phase 5 Non-Goals

Do not treat any of these as implied by Phase 5:

- replacing the shared `AudioEngine`
- making AuraPlay own shell routing
- adding a second router under the music feature
- introducing playlist persistence
- adding durable playback state
- removing `AI/V1` code before migrated UI parity is proven
- rewriting legacy URL helpers that still serve non-migrated paths
- making `GatewayFallbackChain` global infrastructure before a live caller needs it

## Guardrails For The Handoff

- The shell still owns account state, chain scope, and app routing.
- AuraPlay owns music presentation state and music-module composition.
- Keep `ModelContainer` as the shared persistence injection point; do not pass `ModelContext` around globally.
- Leaf SwiftUI views should not talk directly to `AudioEngine`.
- Do not let search logic leak into views or into the global app search stack.
- Storage resolution stays module-owned in `MusicFeature`; legacy app-target URL helpers remain compatibility references until their callers are deliberately migrated.
- If a URL path needs only deterministic normalization, use `URLResolver`. If it needs gateway liveness, use `GatewayFallbackChain` above the resolver.

## Files Worth Opening First

- `Auralis/docs/plans/AuraPlay/phase3-tickets.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-Status.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-Future-Work.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-Gaps.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-LLM-Context.md`
- `Auralis/docs/plans/AuraPlay/Phase3-Followup-Package-Test-Restoration.md`
- `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`
- `MusicFeature/Sources/MusicFeature/App/AuraPlayDependencies.swift`
- `MusicFeature/Sources/MusicFeature/App/MusicFeatureRootView.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Root/AuraPlayEntryView.swift`
- `MusicFeature/Sources/MusicFeature/Services/AuraPlayLibraryRepository.swift`
- `Auralis/Auralis/Assemblies/MusicAssembly.swift`
- `Auralis/MusicApp/AI/V1/NFTMusicPlayerLibraryView.swift`
- `Auralis/MusicApp/AI/Audio Engine/AudioEngine.swift`

## Phase 5 Definition Of Done

A good Phase 5 slice leaves the repo in a state where:

- the Music tab still has one obvious entry point
- the Library surface visibly lives in AuraPlay presentation code
- library data comes from the persisted AuraPlay media graph for scoped wallets
- URL normalization for migrated media/artwork paths uses the Phase 3 resolver seam
- any gateway probing is isolated behind `GatewayFallbackChain`, not mixed into views
- the legacy path is smaller or less central than before
- focused Swift Testing coverage exists for touched presentation/service seams
- in-memory persistence coverage proves scoped library reads before relying on on-disk behavior
- a clean Xcode build passes

## Known Risks Going Into Phase 5

- treating Phase 3 completion as if every downstream caller has already migrated
- leaking media from one wallet or chain into another through an under-scoped library query
- letting the Library migration quietly become a Now Playing or queue rewrite
- duplicating URL-resolution behavior in presentation code because the legacy helpers are familiar
- building UI against raw SwiftData models instead of repository/domain-facing state
- creating visual split-brain between AuraPlay screens and the remaining `AI/V1` path during migration

## Next Engineer Checklist

1. Confirm the current Music tab entry path still routes through `AuraPlayTabRootView`.
2. Identify the active Library browse surface and the smallest slice that can move into AuraPlay presentation code.
3. Trace where that slice prepares artwork and playback URLs.
4. Replace only that migrated slice's URL normalization with `URLResolver`; add `GatewayFallbackChain` only if the slice needs reachability probing.
5. Add focused tests around scoped library reads and URL preparation.
6. Build the project.
7. Update `AuraPlay-Status.md`, `AuraPlay-Gaps.md`, and `Journal.md` if Phase 5 closes a meaningful product or architecture gap.
