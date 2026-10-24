# ADR-001: AuraPlay Architecture

## Status

Accepted; implementation reconciled 2026-10-22

## Context

`AuraPlay` is the rebuild of the Music tab inside `Auralis`, not a separate app or a second shell. At the time this ADR was accepted, the repo still had a live music path under `Auralis/MusicApp/AI/` backed by an app-local audio engine, wallet-scoped NFT data, and shell-owned routing.

Phase 1 needed a clean module boundary for the rebuild without destabilizing the then-shipping path too early.

Current implementation: the old `AI/V1` root and app-local `MusicApp/AI/Audio Engine/AudioEngine.swift` are no longer present. The active Music tab composes `MusicFeatureRootView`; audio playback runs through `AuraPlayAudioEngine.AudioEngineController` wrapped by `AuraPlayPlaybackRuntime`, and video playback runs through `AuraPlayVideoEngine`. The surviving app-owned playlist helpers live under `MusicApp/AuraPlay/Playlist/`, so no music Swift code should live under the old `MusicApp/AI/` namespace.

## Decision

AuraPlay uses native SwiftUI with `@Observable` presentation models, initializer-based dependency injection, and explicit task ownership.

The feature boundary is split between a package and narrow app-owned adapters:

- `MusicFeature/Sources/MusicFeature/`
  Owns AuraPlay domain values, persistence schema and services, feature protocols, receipts, discovery, and the main
  SwiftUI presentation hierarchy.
- `AuraPlayAudioEngine/` and `AuraPlayVideoEngine/`
  Own playback-engine internals independently of the app feature shell.
- `Auralis/MusicApp/AuraPlay/`
  Owns live app adapters, playback composition, platform-specific player bridges, and the explicitly separate legacy
  primary-store playlist compatibility helpers.
- `Auralis/Assemblies/MusicAssembly.swift`
  Builds the live graph and injects package protocols and app adapters. The app composes; it does not re-own the
  feature's domain or persistence model.

## State Ownership

AuraPlay keeps state ownership layered:

1. App shell state
   `ShellStore`, `MainAuraView`, and `AppRouter` remain the source of truth for account selection, tab routing, and app-level transitions.
2. Music composition state
   `MusicAssembly` and `MusicFeatureRootView` receive the active shell scope and wire live services into the package feature.
3. Screen state
   `AuraPlayRootModel` is the first `@Observable` model. It owns AuraPlay-local presentation state and reacts to shell scope changes through explicit updates.
4. Engine state
   Playback state remains owned by injected playback seams. In the current implementation, `AuraPlayPlaybackRuntime` adapts `AuraPlayAudioEngine.AudioEngineController` for audio and the AuraPlay video surface adapts `AuraPlayVideoEngine` for video.

AuraPlay does not create a second app router and does not duplicate playback ownership in SwiftUI views.

## Service Boundaries

The implemented protocol seams include:

- `AuraPlayLibraryRepository`
  Library-facing access to the existing music index and rebuild workflow.
- `AuraPlayPlaybackControlling`
  Playback control surface over the shared audio engine.

These seams are injected through initializers at the composition root and into presentation models. The live implementations wrap existing Auralis services instead of reimplementing them.

- `AuraPlayQueueCoordinating`
- `AuraPlayLogging`
- `AuraPlayArtworkLoading`

These protocols are package-owned; live implementations belong in the app only when they need app infrastructure or
platform composition.

## Historical Migration Plan

Historical Phase 1 migration plan:

1. Keep the then-active app-local audio engine and old music root available while the new boundary is proven.
2. Route the Music tab through a narrow swap seam.
3. Prove repository and playback seams with the AuraPlay root and tests.
4. Migrate the Library surface first because it is mostly read-heavy and lower-risk than playback orchestration.
5. Migrate collection/detail flows next.
6. Migrate Now Playing and queue orchestration only after the service seams are stable.
7. Remove dead `AI/V1` surfaces after parity is established.

Current rule: do not resurrect the old app-local engine or playlist UI paths. The shipping playlist service is package-owned and receipt-backed. App-owned primary-store playlist helpers remain only as an explicitly separate compatibility/test path; the two stores are never silently synchronized.

AuraPlay inventory is network-discovery authoritative. If discovery is unavailable, the feature reports that state instead of silently projecting the primary NFT store into a second persistence model. This preserves one writer and makes provenance and deletion semantics predictable.

Auto-organization is approval-shaped from its first production surface: the current UI runs a receipt-backed dry run only. A future apply operation requires a separate mutation contract and must reuse the active playlist manager rather than writing another playlist database.

## Consequences

- AuraPlay gets a clean namespace without forcing a big-bang rewrite.
- The Music tab can switch roots with a narrow integration diff.
- Tests can replace library and playback behavior without touching the live engine.
- The rebuild stays compatible with the existing shell, account scope, and audio lifetime model.
