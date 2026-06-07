# AuraPlay Future Work

AuraPlay now has a real Phase 2/3 baseline:

- SwiftData container and flat schema
- shared `EOAccount` sync metadata plus the AuraPlay-owned `AuraPlayMediaItem` model
- wallet-scoped sync from the app store into the AuraPlay store
- repository preference for persisted AuraPlay media once a scoped wallet exists
- module-owned storage resolution in `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`
- `URLResolver` wired through `AuraPlayDependencies` and already used by the AuraPlay root for current-track artwork URL preparation
- `GatewayFallbackChain` implemented above the resolver for callers that need HEAD-probed gateway fallback
- June 7, 2026 ship validation for the resolver stack, `MusicFeatureTests`, the app-level ship test, the `Auralis-Full` plan, and the full Xcode build

This file tracks the work that is still intentionally incomplete after the shipped persistence and storage-resolution slices.

## Priority Order

1. Migrate one user-facing music surface at a time into AuraPlay.
2. Add later-phase data features only after the first real AuraPlay browse surface is credible.
3. Prove playback and queue lifecycle behavior on physical devices before broadening scope.
4. Remove the legacy `AI/V1` path only after migrated UI parity is real, not aspirational.

## Highest-Value Incomplete Work

### 1. Move the Library surface onto the AuraPlay presentation stack

Why it matters:

- the current AuraPlay root is still a migration surface, not the real music library experience
- the persisted account-scoped media graph now exists, so Library is the natural first screen to consume it directly
- Library is still the lowest-risk migration slice because it is mostly read-heavy

Success looks like:

- the Music tab’s primary browse surface renders through AuraPlay presentation code
- library items use injected repository, artwork, storage-resolution, logging, and error seams
- library state is clearly sourced from the persisted AuraPlay media graph when a scoped wallet has been mirrored
- migrated artwork and playback URL preparation uses `URLResolver`, with `GatewayFallbackChain` reserved for real reachability probing
- legacy URL helpers stop being copied into new AuraPlay code; old helpers remain only for non-migrated callers
- legacy `NFTMusicPlayerLibraryView` stops being the main browse dependency

### 2. Add three-tier AuraPlay search

Why it matters:

- search is the first major Phase 2 feature still missing from the shipped persistence spine
- the persisted `MediaItem` graph already carries normalized fields that search wants to index and query
- search should stay an AuraPlay-owned domain instead of leaking into the global app search stack

Success looks like:

- one AuraPlay `SearchService` owns trie, CoreSpotlight, and semantic-query coordination
- indexing hooks hang off media mutation paths instead of view code
- AuraPlay search UI can query the persisted graph without depending on the legacy music path

### 3. Add playlists and ordered playlist-item persistence

Why it matters:

- playlists are the first clearly user-owned music artifact not derived from wallet sync
- ordered items prove that the persistence layer can handle durable user curation, not just mirrored NFT media

Success looks like:

- playlist models live in the AuraPlay schema rather than the legacy music folder
- ordered playlist items normalize positions in the service layer
- playlist flows survive relaunch and account-scope changes predictably

### 4. Add durable playback history and playback state

Why it matters:

- the current queue and playback seams expose runtime state, but not durable listening continuity
- playback persistence should stay additive around the shared audio engine, not become a shadow playback controller

Success looks like:

- playback history and resume state persist through relaunch
- the write path is cheap enough to tolerate frequent progress saves
- UI-facing surfaces still read domain-friendly AuraPlay state instead of raw persistence models

### 5. Migrate collection and detail flows

Why it matters:

- the module boundary is only proven once more than the root migration screen can use it
- collection/detail work exercises scope propagation, routing, artwork, and availability presentation

Success looks like:

- collection and item detail screens live under the `MusicFeature` presentation boundary
- routing remains shell-owned and does not fork into a second router

### 6. Migrate Now Playing and queue orchestration last

Why it matters:

- this is the sharpest lifecycle surface in the music stack
- backgrounding, interruption handling, stale loads, and queue ownership all converge here

Success looks like:

- Now Playing uses injected playback and queue seams rather than directly interrogating legacy view internals
- mini player and full player share one coherent playback model
- the queue contract is explicit enough to test without the live engine

### 7. Strengthen the queue seam beyond count snapshots

Current posture:

- the current shipped slice only proves queue visibility through a lightweight snapshot

Next move:

- promote the queue seam into a richer contract that can expose ordered upcoming/history items, active context, and mutation intents

### 8. Add deterministic seeding and integration scenarios

Why it matters:

- this is the real confidence layer for the current media graph and future schema additions
- cascade, uniqueness, scope, and migration bugs are exactly the sort of issue that can pass a clean build and still bite later

Success looks like:

- in-memory seeded AuraPlay graphs exist for previews and tests
- integration scenarios prove wallet sync, replacement, deletion, and persisted-library preference behavior
- later schema additions can land with confidence instead of folklore

### 9. Decide whether `AudioEngine` itself needs deeper decomposition

Why it matters:

- the shared engine still owns download transport, temp-file lifecycle, playback session control, queue state, and presentation-facing state
- AuraPlay now has seams around it, but the engine remains a dense concrete type

Likely follow-on:

- split transport, file lifecycle, queue coordination, and playback-session responsibilities into clearer units if later AuraPlay work starts straining the adapter layer

## Validation Gaps Still Open

### Physical-device execution

- the persistence and storage-resolution seams build and the Phase 3 ship tests pass, but real-device playback validation still needs a deliberate pass
- interruption handling, route changes, background behavior, and rapid track swaps are not the kind of thing to trust to simulator folklore

### Search, playlist, and playback durability validation

- the persistence spine is built, but the higher-level user-owned data features are still absent
- once those land, validation needs to cover indexing correctness, ordered playlist mutations, and durable playback saves under stress

### Performance and polish

- the AuraPlay root is intentionally skeletal
- real performance, visual hierarchy, and interaction quality still depend on the first migrated user-facing surfaces

## Things To Resist

- do not migrate Now Playing before Library and detail flows have proven the architecture
- do not let leaf views talk straight to `AudioEngine` because it is convenient
- do not create a second navigation store inside AuraPlay
- do not treat deferred search, playlist, playback, or UI migration work as “basically done” just because the persistence and storage-resolution seams shipped
- do not remove `AI/V1` code just because the new root compiles
- do not delete the legacy music path before migrated UI parity is real

## Suggested Next Sprint

1. Build the AuraPlay Library screen on top of the repository, artwork, and storage-resolution seams.
2. Run the AuraPlay physical-device suite on a real iPhone against the persisted-library path.
3. Start the three-tier search service only after the Library surface is reading the persisted graph cleanly.
4. Keep playlists and durable playback state behind that, not ahead of it.
