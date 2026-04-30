# ADR-001: AuraPlay Architecture

## Status

Accepted

## Context

`AuraPlay` is the rebuild of the Music tab inside `Auralis`, not a separate app or a second shell. The repo already has a live music path under `Auralis/MusicApp/AI/` backed by a shared `AudioEngine`, wallet-scoped NFT data, and shell-owned routing.

Phase 1 needs a clean module boundary for the rebuild without destabilizing the currently shipping path too early.

## Decision

AuraPlay uses native SwiftUI with `@Observable` presentation models, initializer-based dependency injection, and explicit task ownership.

The module lives under `Auralis/MusicApp/AuraPlay/` with these boundaries:

- `App/`
  Composition root and migration seam from the Music tab.
- `Core/`
  Module-only control types such as the migration stage.
- `Domain/`
  Wallet-and-chain scoped music types.
- `Services/`
  Protocol-backed adapters for library and playback behavior.
- `Presentation/`
  SwiftUI views and `@Observable` presentation models.

## State Ownership

AuraPlay keeps state ownership layered:

1. App shell state
   `ShellStore`, `MainAuraView`, and `AppRouter` remain the source of truth for account selection, tab routing, and app-level transitions.
2. Music composition state
   `AuraPlayCompositionRoot` receives the active shell scope and wires live services into the module.
3. Screen state
   `AuraPlayRootModel` is the first `@Observable` model. It owns AuraPlay-local presentation state and reacts to shell scope changes through explicit updates.
4. Engine state
   Playback state remains owned by the injected playback controller, which currently adapts the shared `AudioEngine`.

AuraPlay does not create a second app router and does not duplicate playback ownership in SwiftUI views.

## Service Boundaries

Phase 1 standardizes these protocol seams:

- `AuraPlayLibraryRepository`
  Library-facing access to the existing music index and rebuild workflow.
- `AuraPlayPlaybackControlling`
  Playback control surface over the shared audio engine.

These seams are injected through initializers at the composition root and into presentation models. The live implementations wrap existing Auralis services instead of reimplementing them.

Additional Phase 1 seams should follow the same pattern:

- `AuraPlayQueueCoordinating`
- `AuraPlayLogging`
- `AuraPlayArtworkLoading`

## Migration Plan From `AI/V1`

The migration stays incremental:

1. Keep the active `AudioEngine` and current `AI/V1` implementation available.
2. Route the Music tab through `AuraPlayTabRootView`, which can swap between the legacy root and the AuraPlay root.
3. Prove repository and playback seams with the AuraPlay root and tests.
4. Migrate the Library surface first because it is mostly read-heavy and lower-risk than playback orchestration.
5. Migrate collection/detail flows next.
6. Migrate Now Playing and queue orchestration only after the service seams are stable.
7. Remove dead `AI/V1` surfaces after parity is established.

## Consequences

- AuraPlay gets a clean namespace without forcing a big-bang rewrite.
- The Music tab can switch roots with a narrow integration diff.
- Tests can replace library and playback behavior without touching the live engine.
- The rebuild stays compatible with the existing shell, account scope, and audio lifetime model.
