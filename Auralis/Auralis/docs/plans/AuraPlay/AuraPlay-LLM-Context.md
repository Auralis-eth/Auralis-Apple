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
- The Music tab routes through `AuraPlayTabRootView`.
- The AuraPlay root currently proves the architecture and dependency wiring, but it is not yet the full migrated music product.
- The legacy implementation still lives under `Auralis/MusicApp/AI/V1/`.

## Architecture In One Pass

- shell state remains owned by `ShellStore`, `MainAuraView`, and `AppRouter`
- AuraPlay owns music-module composition and presentation state only
- `AuraPlayCompositionRoot` wires live dependencies into the module
- `AuraPlayRootModel` is the first `@Observable` presentation model
- playback state still originates from the shared `AudioEngine`, but AuraPlay talks to it through injected seams

## Key AuraPlay Seams

- `AuraPlayLibraryRepository`
  wraps the music-library index and rebuild flow
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

## Important Files

- `Auralis/MusicApp/AuraPlay/App/AuraPlayTabRootView.swift`
- `Auralis/MusicApp/AuraPlay/App/AuraPlayCompositionRoot.swift`
- `Auralis/MusicApp/AuraPlay/App/AuraPlayDependencies.swift`
- `Auralis/MusicApp/AuraPlay/Presentation/Root/AuraPlayEntryView.swift`
- `Auralis/MusicApp/AuraPlay/Services/`
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

- the real Library surface has not been fully migrated into AuraPlay presentation code
- collection and item-detail flows are still migration work
- Now Playing and queue orchestration migration should happen after Library and detail screens
- physical-device playback validation still matters a lot
- the live audio engine remains a dense concrete dependency even though AuraPlay now wraps it

## Safe Next Move

If asked to keep building AuraPlay, start with the Library surface.

Do not start with Now Playing unless the request explicitly overrides that sequencing and accepts the added risk.
