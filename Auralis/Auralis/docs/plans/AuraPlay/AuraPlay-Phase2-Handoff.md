# AuraPlay Phase 2 Handoff

This file is the handoff note for the engineer starting Phase 2. Read this before writing the first migrated feature.

## What Phase 1 Already Locked In

- AuraPlay is an in-project rebuild of the Music tab, not a second app.
- The active integration seam is `AuraPlayTabRootView`.
- The architecture choice is settled: native SwiftUI, `@Observable`, initializer injection, explicit task ownership.
- The first live seams exist for:
  - `AuraPlayLibraryRepository`
  - `AuraPlayPlaybackControlling`
  - `AuraPlayQueueCoordinating`
  - `AuraPlayArtworkLoading`
  - `AuraPlayLogging`
- The shell still owns account state, chain scope, and routing.

## The Right First Move In Phase 2

Migrate the Library surface first.

Why:

- it is mostly read-heavy
- it proves the repository, artwork, logging, and error seams without immediately stepping into the most brittle playback lifecycle work
- it gives the module a real user-facing screen instead of a foundation summary root

## Recommended Migration Order

1. Replace the AuraPlay foundation summary with a real Library screen.
2. Move collection and item-detail presentation into AuraPlay.
3. Promote queue state from simple snapshots to a richer contract.
4. Migrate mini player and Now Playing only after the previous steps are stable.
5. Remove dead `AI/V1` code only after Phase 2 is complete and parity is proven on device.

## Guardrails

- do not add a second router
- do not let leaf views access `AudioEngine` directly
- do not over-abstract before the next real screen exists
- do not remove the legacy path until Phase 2 is complete and the new path has physical-device confidence
- do not confuse “builds cleanly” with “lifecycle-safe”

## Validation Rules For Phase 2

Every substantial migration slice should include:

- a clean build
- focused unit coverage for the new presentation logic or service seam
- a targeted device QA pass if the slice affects playback, interruptions, backgrounding, or artwork flows

## Known Risks Going In

- duplicate playback ownership sneaking into views
- stale-load and interruption bugs hidden behind the shared audio engine
- scope leakage when account or chain changes while music state is onscreen
- visual split-brain between AuraPlay screens and legacy `AI/V1` screens during the migration period

## Files Worth Opening First

- `Auralis/MusicApp/AuraPlay/AuraPlay-README.md`
- `Auralis/docs/decisions/ADR-001-auraplay-architecture.md`
- `Auralis/MusicApp/AuraPlay/App/AuraPlayTabRootView.swift`
- `Auralis/MusicApp/AuraPlay/App/AuraPlayCompositionRoot.swift`
- `Auralis/MusicApp/AuraPlay/Presentation/Root/AuraPlayEntryView.swift`
- `Auralis/MusicApp/AI/V1/NFTMusicPlayerLibraryView.swift`
- `Auralis/MusicApp/AI/V1/NowPlayingView.swift`
- `Auralis/MusicApp/AI/Audio Engine/AudioEngine.swift`
- `Auralis/MusicApp/AI/Audio Engine/MusicLibraryIndex.swift`

## Definition Of A Good Phase 2 Slice

A good slice leaves the repo in a state where:

- the Music tab still has one obvious entry point
- the migrated feature clearly lives in AuraPlay
- the legacy path is smaller than before
- validation confidence went up, not down
