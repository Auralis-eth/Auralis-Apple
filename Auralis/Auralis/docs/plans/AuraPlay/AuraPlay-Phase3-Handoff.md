# AuraPlay Phase 3 Handoff

This file is the handoff note for the engineer starting Phase 3. Read this before writing the first new AuraPlay feature on top of the Phase 2 persistence seam.

## What Phase 2 Already Locked In

- AuraPlay is still an in-project rebuild of the Music tab, not a second app.
- The active integration seam is still `AuraPlayTabRootView`.
- The architecture choice is still settled: native SwiftUI, `@Observable`, initializer injection, explicit task ownership.
- The shell still owns account state, chain scope, and routing.
- The active AuraPlay path now has a real SwiftData persistence spine:
  - `AppModelContainer.make(inMemory:)`
  - `AuraPlaySchemaV1`
  - `AuraPlayMigrationPlan`
  - `AuraPlayWallet`
  - `AuraPlayNFTToken`
  - `AuraPlayMediaItem`
- The live sync path now mirrors wallet-scoped music NFTs from the app store into the AuraPlay store through `LiveAuraPlayLibrarySyncService`.
- `LiveAuraPlayLibraryRepository` now prefers the persisted AuraPlay media graph when a scoped wallet exists and falls back to the legacy indexer otherwise.
- The active AuraPlay root is a Phase 2 persistence seam, not a final migrated Library, Search, Playlist, or durable playback UI.

## The Right First Move In Phase 3

Move the Library surface onto the AuraPlay presentation stack.

Why:

- the persisted wallet/token/media graph now exists and needs a real browse surface to justify itself
- Library is still the safest first migrated product screen because it is read-heavy and lower-risk than Now Playing
- search, playlists, and playback durability all get easier once the Library surface is reading the persisted graph directly

## Recommended Phase 3 Order

1. Replace the current AuraPlay migration root with a real Library screen backed by the persisted AuraPlay media graph.
2. Add the three-tier AuraPlay search service only after Library reads cleanly from the persisted graph.
3. Add playlists and ordered playlist-item persistence after Library and search have stable seams.
4. Add durable playback history and playback state without re-owning the live audio engine.
5. Migrate collection and item-detail presentation into AuraPlay.
6. Leave Now Playing and deeper queue orchestration until the prior steps are stable on device.
7. Remove dead `AI/V1` code only after migrated UI parity is proven on physical devices.

## Guardrails

- do not add a second router
- do not let leaf views access `AudioEngine` directly
- do not inject `ModelContext` globally; keep `ModelContainer` as the only DI-shared persistence object
- do not let search logic leak into views or into the global app search stack
- do not make playlists or playback persistence the new runtime playback owner
- do not remove the legacy path until migrated UI parity is real and device-validated
- do not confuse “persistence exists” with “the user-facing music product is migrated”

## Validation Rules For Phase 3

Every substantial Phase 3 slice should include:

- a clean build
- focused Swift Testing coverage for the touched service, model, or presentation seam
- in-memory persistence coverage before relying on on-disk confidence
- a targeted device QA pass if the slice affects playback, interruptions, backgrounding, route changes, or persisted-library continuity

## Known Risks Going In

- search becoming an accidental second architecture instead of an AuraPlay-owned service
- playlists sneaking in through legacy models instead of the AuraPlay schema
- playback persistence accidentally competing with the shared `AudioEngine` for authority
- scope leakage where persisted media from one wallet or chain appears under another
- visual split-brain between the persisted AuraPlay path and remaining `AI/V1` screens during the migration period

## Files Worth Opening First

- `Auralis/docs/plans/AuraPlay/AuraPlay-Phase2-Implementation-Plan.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-Future-Work.md`
- `Auralis/docs/plans/AuraPlay/AuraPlay-LLM-Context.md`
- `Auralis/docs/decisions/ADR-002-swiftdata-architecture.md`
- `Auralis/MusicApp/AuraPlay/App/AuraPlayTabRootView.swift`
- `Auralis/MusicApp/AuraPlay/App/AuraPlayCompositionRoot.swift`
- `Auralis/MusicApp/AuraPlay/Presentation/Root/AuraPlayEntryView.swift`
- `Auralis/MusicApp/AuraPlay/Persistence/`
- `Auralis/MusicApp/AuraPlay/Services/AuraPlayLibraryRepository.swift`
- `Auralis/MusicApp/AuraPlay/Services/AuraPlayLibrarySyncing.swift`
- `Auralis/MusicApp/AI/V1/NFTMusicPlayerLibraryView.swift`
- `Auralis/MusicApp/AI/V1/NowPlayingView.swift`
- `Auralis/MusicApp/AI/Audio Engine/AudioEngine.swift`

## Definition Of A Good Phase 3 Slice

A good slice leaves the repo in a state where:

- the Music tab still has one obvious entry point
- the new user-facing surface clearly lives in AuraPlay and reads from the intended persisted graph
- deferred later-phase work is still deferred, not half-implied with fake controls or placeholder copy
- the legacy path is smaller than before
- validation confidence goes up, not down
