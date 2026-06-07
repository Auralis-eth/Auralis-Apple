# AuraPlay — Gaps

This is the single living gap log for the AuraPlay rebuild. Each entry names something that should exist for the product to be complete but is not yet in code. Each entry says what it should be, where it should live, and why it matters.

Anything actually shipped lives in `AuraPlay-Status.md`. Do not duplicate.

## Phase 1 Gaps

### CarPlay audio entitlement is missing

- Expected: `com.apple.developer.carplay-audio` declared in `Auralis/Auralis/Auralis.entitlements`.
- Actual: the entitlements file is an empty dict.
- Why it matters: blocks future CarPlay work and any provisioning that expects the entitlement to already be declared.

### `NSMotionUsageDescription` is missing

- Expected: motion usage string in `Auralis/Auralis/Info.plist` to support motion-triggered playlist behavior.
- Actual: not present.
- Why it matters: only matters if motion-triggered playlist switching is still on the roadmap. If that feature has been dropped, close the gap with an explicit decision instead of code.

### Only one secret flows through the build config

- Expected: `REOWN_PROJECT_ID`, `ALCHEMY_API_KEY`, `HELIUS_API_KEY`, `IPFS_GATEWAY_URL`, `ARWEAVE_GATEWAY_URL` all declared in `Secrets.local.xcconfig.template` and mirrored into `Info.plist`.
- Actual: only `AURALIS_ALCHEMY_API_KEY` is declared and mirrored.
- Why it matters: any future feature that needs a Reown project id, Helius key, or a configurable IPFS/Arweave gateway has nowhere to register the value cleanly.

### No typed `AppConfig` access layer

- Expected: a single `AppConfig` type that reads `Bundle.main.infoDictionary` and surfaces a clear developer-facing error when a required key is missing.
- Actual: callers read `Bundle.main.infoDictionary` directly; `AuraPlayModuleConfiguration.live(infoDictionary:)` only validates the music-tab bundle contract.
- Why it matters: missing keys fail silently as empty strings instead of surfacing a clear error at boot.

### No `TestLogger` ships with the logging module

- Expected: a test double for `AuraPlayLogging` that captures emitted events for assertion.
- Actual: only the live `LiveAuraPlayLogger` ships. Tests roll their own fakes.
- Why it matters: every new test that wants to assert on logging has to reinvent the same in-memory capture type.

### Log levels do not include `warning`

- Expected: `AuraPlayLogLevel` covers debug / info / warning / error.
- Actual: `.debug`, `.info`, `.error` only.
- Why it matters: low priority — collapse warnings into info or error today, add the case when something concrete needs it.

### No cross-domain `AppError` umbrella

- Expected: a single app-wide `AppError` that pattern-matches across network, web3, storage, media resolution, playback, and config domains.
- Actual: `AuraPlayError` is module-scoped (`.library`, `.playback`, `.queue`, `.artwork`, `.configuration`, `.mediaResolution`). Other domains throw their own concrete `Error` types.
- Why it matters: UI surfaces cannot pattern-match on a single error type. If a unified surface is wanted later, it has to be retro-added.

### No `recoverySuggestion` and no `AuraPlayError.wrap(_:)`

- Expected: `recoverySuggestion` on `AuraPlayError` and a static `wrap` helper that turns unknown `Error` values into typed cases.
- Actual: `AuraPlayError` implements `errorDescription` and has domain-specific static mappers including `mediaResolution(_:)`. There is no generic `wrap` and no `recoverySuggestion`.
- Why it matters: error messages reaching the UI carry no actionable recovery copy; arbitrary `Error` instances cannot be normalized without manual matching.

### SwiftLint is missing the strict-safety opt-ins

- Expected: `force_unwrapping` and `implicitly_unwrapped_optional` enabled, plus a line-length cap and tightened file / type body limits.
- Actual: only `empty_count`, `first_where`, `sorted_imports`, `toggle_bool` are opted in. `line_length`, `file_length`, and `type_body_length` are explicitly disabled.
- Why it matters: force-unwrap regressions slip in without lint signal; long files and types are not flagged.

### The ticketed-TODO rule is AuraPlay-only

- Expected: every part of the codebase requires TODOs to reference a ticket ID.
- Actual: `auraplay_ticketed_todo` only applies under `Auralis/MusicApp/AuraPlay`. Elsewhere, untagged TODOs are accepted.
- Why it matters: the rest of the codebase can accumulate untracked TODO debt.

### CI jobs are not split

- Expected: separate `lint`, `build`, and `test` jobs so failures show up as distinct checks.
- Actual: one job `lint-build-test` runs all three steps sequentially.
- Why it matters: small workflow cleanliness gap, no functional gap.

### No secrets injection in CI

- Expected: CI writes `Secrets.local.xcconfig` from GitHub Secrets so the build sees real keys.
- Actual: the workflow does not touch `Secrets.local.xcconfig`. The build compiles with the placeholder empty key.
- Why it matters: any test that actually needs a live API key will silently see an empty string.

### No DerivedData / SPM cache and no xcresult artifact upload

- Expected: `actions/cache` on `DerivedData` and the SPM cache, plus an `xcresult` artifact upload on failure.
- Actual: neither is wired.
- Why it matters: CI is slower than necessary, and failed-test triage requires re-running locally rather than downloading the result bundle.

### No top-level README or CONTRIBUTING

- Expected: `README.md` and `CONTRIBUTING.md` at the repo root, plus a `docs/decisions/INDEX.md` listing all ADRs.
- Actual: none of the three exist. ADRs 001–004 are discoverable only by directory listing.
- Why it matters: a new engineer cannot follow a single onboarding doc to a working build.

## Phase 2 Gaps

### Versioned schema and migration plan are not in place

- Expected: `AuraPlaySchemaV1` defined as a `VersionedSchema` with a `Schema.Version`, and an `AuraPlayMigrationPlan` conforming to `SchemaMigrationPlan` that the container is built against. New models register through the versioned schema; new releases add stages without modifying the v1 enum.
- Actual: `AuraPlaySchema` is a plain enum exposing a flat `models` array. `AuraPlayModelContainer` builds a `ModelContainer` directly from that schema without passing a migration plan. No `AuraPlayMigrationPlan` type exists.
- Why it matters: the first additive schema change has no migration hook to extend. The next model that lands should be the one that motivates introducing the versioned schema.

### AuraPlay-owned wallet service is not built

- Expected: an `@ModelActor` wallet service in `MusicFeature` exposing upsert / fetchAll / fetchActive / deactivate / deleteAll operations against the AuraPlay read path.
- Actual: the shared `EOAccount` `@Model` already exists in `AuralisPrimaryModels/Sources/AuralisPrimaryPersistence/EOAccount.swift` (keyed by `address`, with a cascading `nfts: [NFT]` relationship and per-chain `auraPlaySyncStateRawValue` metadata exposed through `auraPlayLastSyncedAt(for:)`, `markAuraPlaySynced(on:at:)`, `clearAuraPlaySyncState(for:)`, and `clearAllAuraPlaySyncState()`). AuraPlay carries wallet scope through `AuraPlayLibraryScope` and the sync service mutates `EOAccount` directly. There is no AuraPlay-owned wallet service surface.
- Why it matters: AuraPlay does not need a second wallet model — it needs a deliberate decision on whether the wallet service should live in `MusicFeature` over the shared model or whether shell-level account services should be extended for AuraPlay's needs (ENS storage, scope history, multi-wallet UI).

### AuraPlay-owned NFT token service is not built

- Expected: an `@ModelActor` NFT token service that takes `Sendable` DTOs across the actor boundary (because `@Model` is not `Sendable`) and supports batched upserts in a single save, scoped to AuraPlay's read path.
- Actual: the shared `NFT` `@Model` already exists in `AuralisPrimaryPersistence` with a composite uniqueness constraint on `(contract, tokenId, networkRawValue, accountAddressRawValue)` and an inverse relationship to `EOAccount`. AuraPlay also denormalises NFT origin inline on `AuraPlayMediaItem` (`sourceNFTID`, `contractAddressRawValue`, `tokenID`, `tokenType`). There is no AuraPlay-owned NFT token service and no DTO surface.
- Why it matters: AuraPlay currently mirrors NFT origin into `AuraPlayMediaItem` instead of pointing at the shared `NFT` graph through a service. Any classification split — including non-playable NFTs — needs a deliberate decision about whether to extend the shared model, introduce an AuraPlay-owned projection, or keep the denormalised mirror.

### `AuraPlayMediaItem` has no user-override fields or display fallbacks

- Expected: `overrideTitle`, `overrideCreator`, `overrideArtworkURL`, `overrideGenre` fields written only by user action, plus computed `displayTitle` / `displayCreator` / `displayArtworkURL` properties that prefer the override and fall back to the sync-owned field. A typed `MediaItemOverride` value plus a service-level `applyUserOverride(_:id:)` mutation path.
- Actual: `AuraPlayMediaItem` has no override-shaped fields and no override mutation path.
- Why it matters: user-curated metadata edits cannot survive a sync because every field is treated as sync-owned.

### `MediaItemSort` and `MediaItemFilter` typed surfaces are not built

- Expected: a `MediaItemSort` enum (`dateAdded`, `titleAZ`, `creatorAZ`, `duration`, `lastPlayed`) and a `Sendable MediaItemFilter` struct (chain, media type, duration range, unplayed-only). A `MediaItemService.fetchSorted(sort:filter:)` operation that resolves them.
- Actual: sort and filter logic lives in ad-hoc `FetchDescriptor` builders inside `AuraPlayPersistenceDescriptors.swift`; there is no public typed surface.
- Why it matters: Library UI work has nothing to bind onto for filter chips; every filter has to be added by hand.

### `AuraPlayMediaItem` is missing relationship inverses to playback state and search index

- Expected: relationships from `AuraPlayMediaItem` to `PlaybackState` and `SearchIndex` with `.cascade` delete rules so deleting a media item removes its derived rows.
- Actual: neither relationship exists because the related models do not exist.
- Why it matters: once `PlaybackState` and `SearchIndex` land, they have to be wired up at the same time. Plan for the relationship change as part of those models, not after.

### Three-tier search is not built

- Expected: one `SearchService` actor as the single public search API, exposing `autocomplete(prefix:) -> [String]` (synchronous) and `search(query:) async -> SearchResult` (async). It owns three independent tiers wired up behind it:
  - **Tier 1 — In-memory trie (Swift stdlib).** `TrieNode` (`children: [Character: TrieNode]`, `mediaItemIDs: Set<String>`) and an immutable `Trie` value, rebuilt wholesale after each NFT sync by a `TrieBuilder` `@ModelActor` that fetches all media items, tokenizes `displayTitle` + `displayCreator` + `collectionName` via `NLTokenizer(unit: .word)`, lowercases, and inserts. The active trie is published to the main actor via an `@Observable TrieIndex`; the previous trie stays live during rebuild. Target: build under 200 ms for 10,000 items; lookup under 1 ms.
  - **Tier 2 — CoreSpotlight.** A `SpotlightIndexer` class (not an actor — `CSSearchableIndex` callbacks are not async-safe; uses a private serial `DispatchQueue` instead) batches `CSSearchableItem`s 100 at a time under domain `com.auraplay.media`. Each item carries a `CSSearchableItemAttributeSet` (`contentType` = `.audio` or `.video` based on `hasVideo`; title / artist / album / contentDescription / duration / thumbnailURL populated from display fields). `NSUserActivity` is updated on every playback start so Spotlight relevance boosts naturally. Query goes through `spotlightSearch(query:) async throws -> [String]` wrapping a `CSSearchQuery` in `withCheckedContinuation`, capped at `fetchLimit: 25` with a 3-second timeout that cancels and returns partial results. Target: under 50 ms.
  - **Tier 3 — Semantic embeddings.** A `SearchIndex` `@Model` keyed by `mediaItemId`, with `@Attribute(.externalStorage) var embeddingVector: Data?` (Float32 vector via `withUnsafeBytes` / `bindMemory(to: Float.self)`), `embeddingModelVersion`, `indexedAt`, and an inverse relationship back to `MediaItem`. An `EmbeddingService` `@ModelActor` processes up to 50 unindexed items per `BGAppRefreshTask` call using `NLEmbedding.sentenceEmbedding(for: .english)` (falling back to `wordEmbedding` when the sentence model is unavailable), casting Float64 vectors to Float32. An `@Observable EmbeddingProgress` (`pendingCount`) lets the Library show an "Indexing…" banner. Query runs entirely on the actor thread via Accelerate (`vDSP_dotpr` for dot product, `vDSP_svesq` + `sqrt` for magnitudes), filters cosine similarity ≥ 0.72, sorts descending, and returns up to 25 `(id, score)` pairs. Target: under 100 ms.
  - **Merge.** `search(query:)` runs Tiers 2 and 3 in parallel via `async let`, blends with weights spotlight × 0.55 + semantic × 0.45 + a 0.15 overlap boost when an id appears in both, deduplicates, sorts descending. Surface Spotlight progressively if Tier 2 returns before Tier 3; fall back to expanded Tier 1 autocomplete if both tiers time out. The result is a `SearchResult` struct (`ids`, `spotlightCount`, `semanticCount`, `overlapCount`) so debug overlays in dev builds can inspect tier participation.
- Actual: the normalized search keys on `AuraPlayMediaItem` are the only search affordance. None of `SearchService`, `Trie`, `TrieIndex`, `TrieBuilder`, `SpotlightIndexer`, `EmbeddingService`, `EmbeddingProgress`, `SearchIndex`, or `SearchResult` exist.
- Why it matters: search remains a future-phase item, and UI work cannot assume any of the three tiers exist. The whole-tier-set should land together behind `SearchService` so callers do not have to assemble it.

### Spotlight lifecycle hooks from media and wallet services are not wired

- Expected: `MediaItemService.upsertAll(_:)` re-indexes new and modified items via `SpotlightIndexer.indexItems(_:)`. `MediaItemService.applyUserOverride(_:id:)` re-indexes the single affected item. `WalletService.deleteAll()` calls `SpotlightIndexer.deleteAll(domain: "com.auraplay.media")` so dropping a wallet purges its CoreSpotlight footprint.
- Actual: none of these hooks exist because neither the indexer nor the wallet service is built; even `AuraPlayMediaItemService` has no Spotlight call site.
- Why it matters: when search lands, the hooks have to land at the same time or the index will drift out of sync with the persisted graph.

### Background embedding work is not scheduled

- Expected: a registered `BGAppRefreshTask` that drives `EmbeddingService.processQueue(limit: 50)` so semantic indexing happens off the foreground task and resumes after relaunch.
- Actual: no background task identifier is declared in `Info.plist`, and no scheduler call is made anywhere.
- Why it matters: without background scheduling, semantic indexing only happens while the app is foregrounded, which makes Tier 3 unreliable for long libraries.

### Embedding fixtures for deterministic semantic tests are not built

- Expected: an `EmbeddingFixtures` test helper that ships pre-computed Float32 vectors for the canonical seeded media items so semantic-search assertions can compare against known scores without re-running `NLEmbedding` in every test.
- Actual: not built.
- Why it matters: when `EmbeddingService` lands, semantic-search tests need a stable corpus; otherwise tests will drift the moment Apple updates the embedding model.

### Playlist persistence and ordered playlist items are not AuraPlay-shaped

- Expected: a playlist model with smart/AI flags, smart-query data, iCloud sync key, and a cascading relationship to a `PlaylistItem` carrying `position` + `addedAt`, plus a compound `#Unique` constraint on `(playlist, mediaItem)` and a `@ModelActor PlaylistService` that maintains a contiguous, gapless `position` sequence after every add / remove / reorder through a single save.
- Actual: the shared `Playlist` `@Model` exists in `AuralisPrimaryPersistence` (`@Attribute(.unique) id: UUID`, `title`, `imageData`, `tracks: [NFT]` via `\NFT.playlists` inverse), but it stores tracks as an unordered `[NFT]` array — no `PlaylistItem`, no `position`, no compound unique constraint, no smart/AI flag fields, and no playlist service.
- Why it matters: AuraPlay-shaped playlist work needs either to extend the shared model with ordered `PlaylistItem` rows and an AuraPlay service, or to introduce an AuraPlay-owned playlist model alongside it. Decide deliberately before adding either ordering or smart-playlist support.

### Playback history is not persisted

- Expected: a `PlaybackState` `@Model` (position-ms, duration-ms cache, play-count, completed-count, last-played-at) keyed by media item, with `@Attribute(.preserveValueOnDeletion)` on identifying fields so persistent-history tombstones can drive Smart Resume after a token is burned or transferred. A `@ModelActor PlaybackStateService` with `autosaveEnabled = false` and an explicit save per update, sized for an update every five seconds during playback.
- Actual: not built. Playback state remains transient inside the shared `AudioEngine`.
- Why it matters: no "recently played" library row, no resume-from-position, no analytics surface for Smart Resume work.

### Sendable DTOs for cross-actor work are not defined

- Expected: `Sendable` DTOs (`NFTTokenDTO`, `MediaItemDTO`, `PlaylistDTO`, `PlaybackStateDTO`) that the persistence services accept and emit so `@Model` objects never cross actor boundaries.
- Actual: only `AuraPlayMediaItemService` exists today and it does not yet route through DTOs.
- Why it matters: once additional `@ModelActor` services land, the DTO pattern needs to land with them or the actor boundary will leak `@Model` references.

### No deterministic seeder

- Expected: a tiered seeder (`.minimal`, `.standard`, `.large`) with deterministic counter-based IDs (`wallet-001`, `media-001`) and fixed-epoch dates that populates a `ModelContainer` for tests and SwiftUI previews. Coverage spans audio-only / video-only / audio+video / non-playable items, all six chains, items with and without ENS names / overrides / embedding vectors, a Smart and an AI-generated playlist, and varied `PlaybackState` rows. The seeder also primes the CoreSpotlight mock index and exposes `EmbeddingFixtures` so semantic-search tests can run without re-embedding. It lives in a test-only `AuraPlayTestSupport` package and is never linked into the app target.
- Actual: shared test-container helpers in `AuralisTestSupport` exist, but there is no tiered AuraPlay seeder and no Spotlight or embedding fixture surface.
- Why it matters: previews and snapshot tests cannot share a single stable dataset. Each test rebuilds fixtures locally — exactly the drift problem worth eliminating.

### No cross-entity integration suite

- Expected: a Swift Testing suite that exercises the full model graph end-to-end against an in-memory container — cascade delete from wallet down through media item (including the CoreSpotlight purge), playlist integrity after media-item deletion, recently-played ordering, unplayed query, user-override round-trip, the three-tier search round-trip (trie `autocomplete`, Spotlight mock query, semantic query against `EmbeddingFixtures`), persistent-history tombstone retrieval, and uniqueness-constraint behavior.
- Actual: focused MusicFeature tests cover schema registration, in-memory container boot, and persisted-library preference, but most scenarios reference entities and services that do not yet exist.
- Why it matters: as soon as more models land, this is where the safety net needs to grow. Plan the scenarios alongside the model that lands first.

### `AuraPlayIntegrationTests` target does not exist

- Expected: a separate integration-test target so end-to-end scenarios can be filtered out of fast CI lanes and run as a fourth job.
- Actual: there is no such target; CI runs all `MusicFeatureTests` together.
- Why it matters: small organizational gap — flag if integration runtimes start dominating CI minutes.

## Phase 3 Gaps

No open Phase 3 storage-resolution gaps are currently tracked here. The module-owned resolver stack is implemented under `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`, wired through `AuraPlayDependencies`, and validated by the June 7, 2026 ship pass.

Any follow-on caller migration should be tracked under the downstream phase that consumes it. The unrelated package-test restoration work found during the broader ship sweep is tracked separately in `Phase3-Followup-Package-Test-Restoration.md`.

## Phase 5 Gaps

### Downstream media URL callers have not fully migrated to storage resolution

- Expected: every migrated AuraPlay metadata, artwork, audio-engine, and image-classifier path that prepares decentralized or remote media URLs routes deterministic normalization through `URLResolver`, and uses `GatewayFallbackChain` only when reachability probing is actually needed.
- Actual: `URLResolver` is wired through `AuraPlayDependencies` and the AuraPlay root uses it for current-track artwork URL preparation, but legacy metadata fetch, audio engine loading, and image-classifier paths still use older helpers such as `URLConverter.convertToPreferredHTTPS` and `URL.toPinataGatewayURL()`.
- Why it matters: Phase 3 built the storage-resolution seam, but product confidence only arrives when real caller paths stop duplicating gateway and URI-normalization behavior.

## How To Use This File

- Pick gaps off this list deliberately when a downstream phase needs them.
- When a gap is closed, delete its entry and add a one-line note in `AuraPlay-Status.md` reflecting the new reality.
- Each new phase should add its own gap entries here under a `## Phase N Gaps` heading. Do not start a separate file per phase.
