# Changelog

All notable product-facing and ship-relevant changes should be recorded here.

## Unreleased

### Added
- Introduced the `AuraPlay` module foundation as the rebuild seam for the Music tab, with explicit composition, dependency, logging, library, playback, queue, artwork, and bundle-configuration boundaries.
- Added CI and lint guardrails for AuraPlay module work.
- Added source-backed contract tests for privacy-manifest and bundle metadata expectations around AuraPlay.
- Added documentation artifacts for AuraPlay architecture, Phase 2 handoff, future work, device QA, and UI audit.

### Changed
- Routed the Music tab through `AuraPlayTabRootView`, which now acts as the migration seam between the legacy implementation and the new AuraPlay path.
- Updated app configuration and metadata to support the new AuraPlay migration work and wallet-app integration requirements.

### Planned
- The legacy music implementation under `Auralis/MusicApp/AI/V1/` remains in place during Phase 2 migration work.
- Legacy music code is intended to be removed only after Phase 2 is complete and feature parity is proven.
