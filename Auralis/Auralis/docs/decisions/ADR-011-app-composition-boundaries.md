# ADR-011: App Composition Uses Narrow Assembly-Owned Dependencies

## Status

Accepted and implemented.

## Context

The app previously passed a `ShellServiceHub` service locator through shell and presentation code. Views could reach through that shared container to construct unrelated infrastructure, obscuring ownership and making tests depend on a broad mutable graph.

## Decision

- App infrastructure is composed by focused assemblies under `Auralis/Assemblies/`.
- Views and feature roots receive only the collaborators required by their feature.
- `ShellStore` remains the state-machine boundary for shell actions and effects.
- Live adapters stay in the app target; reusable protocols and domain behavior stay in their owning packages.
- New features must extend an existing focused assembly or introduce a focused assembly instead of recreating a general service locator.

## Evidence

- No `ShellServiceHub` type or call site remains in Swift source.
- `AccountAssembly`, `HomeAssembly`, `MainTabAssembly`, `MusicAssembly`, `PolicyAssembly`, `PrivacyAssembly`, `ProviderAssembly`, `ReceiptAssembly`, `RuntimeAssembly`, `SearchAssembly`, `ShellAssembly`, and `TokenHoldingsAssembly` provide the current composition boundaries.
- Architecture boundary and shell dependency-builder coverage protects the package/import and construction seams.

## Consequences

- Dependency ownership is explicit at construction sites.
- Presentation code cannot discover unrelated services through a shared locator.
- Test fixtures can replace narrow collaborators without rebuilding the full app graph.
