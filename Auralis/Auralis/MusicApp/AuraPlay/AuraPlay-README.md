# AuraPlay

AuraPlay is the in-place rebuild of the Auralis Music tab.

## Where It Lives

- `App/`
  Composition root, dependency container, and the migration seam from `MainTabView`.
- `Core/`
  Module-only control types and configuration snapshots.
- `Domain/`
  Wallet-and-chain scoped music models plus the AuraPlay error surface.
- `Services/`
  Protocol seams and live adapters for library, playback, queue, artwork, and logging behavior.
- `Presentation/`
  SwiftUI views and `@Observable` presentation models for the rebuilt root.

## Current Architecture

AuraPlay uses native SwiftUI with `@Observable` presentation state and initializer-based dependency injection.

The active root today is `AuraPlayCompositionRoot`, which receives shell scope plus an `AuraPlayDependencies` container. The module does not own app-level routing or account state; those remain at the shell boundary.

## Migration Notes

- The live music implementation still exists under `Auralis/MusicApp/AI/V1/`.
- `AuraPlayTabRootView` is the swap seam that can point the Music tab at the legacy root or the AuraPlay root.
- Library migration comes first because it is read-heavy and lower-risk than queue and playback orchestration.
- Now Playing should move only after the repository, playback, queue, and artwork seams are proven.
