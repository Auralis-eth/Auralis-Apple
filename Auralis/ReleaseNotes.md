# Release Notes

## Current Ship Snapshot

### What Shipped
- A wallet-based Aura app shell that restores account state and routes across Home, News Feed, Gas, Music, Receipts, Search, and Settings.
- NFT discovery and refresh backed by provider fetches, retry-aware error modeling, and local SwiftData persistence.
- Guest pass onboarding for safe exploration with public wallet content.
- Music playback powered by the active `MusicApp/AI/` audio engine path, including mini-player and detail views.
- Search across local accounts, NFTs, and token holdings with scoped routing into profile, token, and NFT destinations.

### Notable Fixes
- Provider failures now have explicit blocking and degraded presentations instead of collapsing into generic refresh failure behavior.
- Shell state restoration and deep-link handling were tightened so cold-start and account-switch flows resolve more predictably.
- Chain-scoped refresh and account-switch flows were reinforced to avoid stale navigation and stale data crossover.

### Known Limitations
- Not every surface is equally complete; some tabs still include scaffold or placeholder behavior.
- Full receipt support is not finished yet.
- Audio availability still depends on successful engine initialization at launch.
- A few large files remain overdue for decomposition, which raises maintenance risk even if current behavior works.

### Deferred Nice-to-Haves
- Additional UX polish for sparse-data and first-run states.
- Deeper release hardening for placeholder tabs and incomplete receipt flows.
- More aggressive decomposition of oversized files and service boundaries.
- Expanded release-process artifacts and manual QA coverage beyond the current ship snapshot.
