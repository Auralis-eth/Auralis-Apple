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

### Versioned schema and migration plan are in place

- Expected: `AuraPlaySchemaV1` defined as a `VersionedSchema` with a `Schema.Version`, and an `AuraPlayMigrationPlan` conforming to `SchemaMigrationPlan` that the container is built against. New models register through the versioned schema; new releases add stages without modifying the v1 enum.
- Actual: resolved in Phase 14. `AuraPlaySchemaV1`, `AuraPlaySchemaV2`, and `AuraPlayMigrationPlan` now exist, and `AuraPlayModelContainer` opens through the migration plan.
- Why it matters: future schema changes now have an explicit staged migration hook instead of relying on an unversioned flat model list.

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

### `AuraPlayMediaItem` is missing relationship inverses to search index

- Expected: a relationship from `AuraPlayMediaItem` to `SearchIndex` with a `.cascade` delete rule so deleting a media item removes its derived search row.
- Actual: `AuraPlayPlaybackState` now exists as a standalone playback-position row keyed by media ID, but no `SearchIndex` model exists.
- Why it matters: when search lands, the index relationship should land with it instead of leaving orphaned derived search rows.

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

### Playback history analytics and tombstone policy use an AuraPlay-owned contract — RESOLVED FOR PHASE 13 (2026-07-25)

- Was: the older April ticket expected persistent-history tombstones with deletion-preserved fields on playback state, while the current codebase had no such infrastructure.
- Decision: Phase 13 accepts the explicit `AuraPlayPlaybackPositionTombstone` model as the recovery contract. It stores exact token identity plus resumable position/play-count data during sync reconciliation and restores only when the same on-chain token returns.
- Remaining follow-up: a broader analytics model with completed-count reporting can still land later, but it is no longer a Phase 13 Smart Resume blocker.

### Sendable DTOs for cross-actor work are not defined

- Expected: `Sendable` DTOs/snapshots (`NFTTokenDTO`, `MediaItemDTO`, `PlaylistDTO`, `PlaybackStateDTO`) that the persistence services accept and emit so `@Model` objects never cross actor boundaries.
- Actual: discovery and media persistence use `NFTTokenDTO` / `MediaItemDTO`, media query windows return `MediaItemQueryItem` snapshots, and playlist item reads expose `AuraPlayPlaylistItemSnapshot`. A complete DTO surface for every playlist and playback-state operation is not built yet.
- Why it matters: the pattern is now established, but every new `@ModelActor` service method still needs to avoid returning live SwiftData models across isolation.

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

No open Phase 5 storage-resolution-migration gaps are currently tracked here. Every AuraPlay media-URL caller now routes through the module-owned stack: the Phase 5 discovery pipeline (`MetadataFetcher`, `MediaClassifier`, `MediaItemArtworkPrefetcher`) uses `GatewayFallbackChain`/`URLResolver`, both library-sync artwork paths (`LiveAuraPlayLibrarySyncService` in the app target and `SwiftDataMusicLibraryIndexer` in the package) normalize through `URLResolver`, the audio-engine load path resolves decentralized URIs through the runtime's `GatewayFallbackChain`, and the video gateway-fallback resolver derives its host list from `AuraPlayStorageResolutionConfiguration` instead of a hard-coded copy.

The legacy helpers (`URLConverter.convertToPreferredHTTPS`, `URL.toPinataGatewayURL()`, `URL.sanitizedRemoteMediaURL(from:)`) now serve only non-AuraPlay shell paths (`NFTKit`, `AuralisPrimaryModels`); retiring those is shell cleanup, not an AuraPlay gap.

## Phase 6 Gaps

### Host app has not fully signed off the audio-engine release gates

- Expected: the host app wires `AuraPlayAudioEngine` into real playback flows with user controls, route selection, cache persistence, app-owned media adapters, persisted loudness measurement updates, disciplined Now Playing publication, `AVInitialRouteSharingPolicy = LongFormAudio`, and completed physical-device QA from `AuraPlay-Physical-Device-QA-Suite.md`.
- Actual: the package-side Phase 6 infrastructure and host UI wiring are implemented: Settings, Now Playing, and the mini player expose EQ, custom 10-band EQ, normalization, AutoMix, route, cache/offline, buffering/download progress, recovery, transition status, and transient typed playback warnings. Release readiness still depends on real-device sign-off for AirPods, interruptions, Lock Screen, background, audible gaplessness, poor-network buffering, offline launch, and battery behavior.
- Why it matters: `AVAudioEngine` package readiness and UI wiring are still not the same as a shippable playback experience. Route changes, interruptions, Lock Screen controls, AirPods behavior, AirPlay, audible gaplessness, and battery behavior need the real app, real media, and physical hardware before the phase can be closed.

## How To Use This File

- Pick gaps off this list deliberately when a downstream phase needs them.
- When a gap is closed, delete its entry and add a one-line note in `AuraPlay-Status.md` reflecting the new reality.
- Each new phase should add its own gap entries here under a `## Phase N Gaps` heading. Do not start a separate file per phase.

## Phase 9/10 Gaps

### Snapshot baselines render on the macOS host, not an iOS simulator

- Expected: eventually, an iOS-simulator snapshot lane so baselines match shipping pixels.
- Actual: `LibraryAndPlayerSnapshotTests` renders through `NSHostingView` on macOS because app-hosted tests crash under the current Xcode beta and `swift test` builds for the host. The suite is deterministic and stable across runs, but the pixels are macOS pixels.
- Why it matters: a future iOS snapshot lane requires re-recording all baselines; do not mix baselines from both platforms.

### Library populates only when network discovery is available

- Context: `NFTSyncCoordinator` (network discovery) is now the single authoritative writer of `AuraPlayMediaItem`. `LiveAuraPlayLibrarySyncService` no longer writes/replaces media rows — it only records the per-scope sync timestamp (`markSynced`) and classification receipts. This removed a bug where the audio-only local-inventory projection's `replaceAll` deleted discovery-written video and network-only items for the visible scope on every appearance.
- Residual: when discovery is unavailable (e.g. missing Alchemy/Helius keys → `NoOpAuraPlayNFTDiscoverySyncService`), nothing projects the already-downloaded local `NFT` inventory into `AuraPlayMediaItem`, so the library can be empty even though local NFT rows exist. This is an accepted tradeoff (the local inventory needs the same keys to populate anyway).
- Follow-up if needed: fall back to a non-destructive local projection only when discovery is the no-op service, or fold video/animation-URL handling into the local projection so it is no longer audio-only.

### Physical-device QA and manual accessibility audit are outstanding

- Expected: the device QA suite in `AuraPlay-Physical-Device-QA-Suite.md` executed on hardware (PiP, AirPlay, subtitles, speed, routes, interruptions), plus an Accessibility Inspector pass over Library and Player.
- Actual: everything code-side is automated-tested; these two gates need a human with a device.
- Why it matters: they are the last release gates for Phases 9/10.

## Phase 11 (Search) Gaps

### Assistant result-quality evaluation is a seed, not real coverage

- Expected: a meaningful evaluation corpus for `SearchAssistantService` that scores real result relevance (precision/recall over representative queries), not just structural round-trips.
- Actual: `SearchAssistantEvaluationTests` is a deliberately small seed whose `subject(from:)` returns a hand-rolled fixture stub (`fixtureReturnedIdentifiers`), so it scores harness math, not the real assistant. It does not drive `SearchAssistantService` / the live `SpotlightSearchTool` pipeline.
- Update (2026-07-19): the on-device model reports `.available` on the physical iOS 27.0 test device, so a model-driven evaluation is now genuinely runnable here — the blocker is no longer the runtime, it is the missing work: (1) point `subject` at the real `SearchAssistantService` against a seeded CoreSpotlight test domain, (2) grow the corpus to representative per-domain queries with precision/recall (not just coverage), (3) keep it out of the fast lane since live-LLM + async Spotlight indexing is nondeterministic.
- Why it matters: until the eval drives the real pipeline, assistant result quality is still unverified even though the path now runs.

### iOS-27-only assistant stages: hardened in code, runtime validation still pending

- Done (2026-07-19): `AuralisMediaCapabilityStage` now scores off the structured Spotlight metadata tokens the indexer already emits (`mediaKind`, `isPlayable`, `artistName`, `collectionName`) with named weight constants, and no longer scans free text for `"music"`/`"artist:"` substrings. `AuralisReceiptRollupStage.receiptValue` reads grouping values straight from structured tokens and dropped the fragile `"Trigger: …"` free-text parsing — this also fixed a latent bug where chain grouping looked up a non-existent `receiptChain` token instead of the shared `chain` token. Table cells are now formatted by pattern-matching the typed `SearchResultsTable.Value` at the source, so `SearchAssistantTableView.cleanedCellValue` (which string-stripped `.string(...)` syntax) is deleted. Unit tests live in `SearchAssistantStageTests` (structured scoring, threshold filtering, synonym mapping, receipt grouping incl. the chain regression, typed cell formatting).
- Validated (2026-07-19): run on a physical iOS 27.0 device, all 11 stage/cell/evaluation-seed tests pass, and the pre-existing `SearchSpotlightSupportTests` stage tests still pass (no regression from the refactor). The app-hosted test crash seen under the Xcode beta simulator did not occur on device. Unblocking the device lane required one fix to the vendored `CodeScanner` package: `ScannerViewController.useSimulatedCodeFromButton` referenced the simulator-only `sendSimulatedCode()` without a `#if targetEnvironment(simulator)` guard, which broke every device build.

## Phase 12/13 (Ecosystem / Intelligence) Gaps

### Smart Shuffle play-count weighting is inert — RESOLVED (2026-07-23)

- Was: `playbackHistories()` always built `SmartShufflePlaybackHistory` with `playCount: 0`, so the `1 / (playCount + 1)` term in `SmartShuffleWeighting.weight` was dead and Smart Shuffle was recency-only.
- Fix: `AuraPlayPlaybackPositionState` now persists `playCount`, `AuraPlayPlaybackPositionStateService.markCompleted` increments it, `playbackHistories()` threads it through, and `AuraPlayPlaybackPositionTombstone` carries it so Smart Resume restores it. Covered by `AuraPlayPhase13IntelligenceTests`.

### Unparseable incoming deep links are silently ignored — DECISION: intended (2026-07-23)

- `MainAuraView.handleIncomingURL` routes through `IncomingDeepLinkPolicy`, which logs and drops URLs that fail to parse. This is the intended product behavior for user-tapped bad links (no "link not supported" alert); tests assert the drop. No further action.

### Collection share identifier can double-prefix the chain — RESOLVED (2026-07-23)

- Was: `AuraPlaySharePolicy.collectionShareRequest` fell back to `group.id` (already `"chain|contract"`) when `contractAddress` was nil, and the handler prefixed the chain again → `"chain|chain|contract"`.
- Fix: the share builder now emits a bare identifier (strips the leading `"<chain>|"` from `group.id`), and `ShellCollaborators` guards against an already-qualified `"chain|…"` identifier before re-prefixing. Round-trip covered by `AuraPlayEcosystemTests`.

### More Like This per-item embedding gate — RESOLVED (2026-07-25)

- Was: the context action was only gated by global embedding availability.
- Fix: `AuraPlayRootModel` now maintains a scoped set of media IDs with stored embeddings and hides the action per item. The set is scoped by account/chain, cleared on scope changes, and not fetched when embeddings are globally unavailable. Covered by `AuraPlayFoundationBoundaryTests`.

## Phase 14 Gaps

### Phase 14 artifacts exist, but manual release gates are not signed off

- Expected: Phase 14 produces the final accessibility findings, error-presentation audit, App Review checklist, master QA checklist, and known-limitations release notes described in `AuraPlay-Phase14-Settings-Accessibility-Hardening-Plan.md`.
- Actual: the artifacts now exist:
  - `AuraPlay-Phase14-Accessibility-Findings.md`
  - `AuraPlay-Phase14-Error-Presentation-Audit.md`
  - `AuraPlay-Phase14-App-Review-Checklist.md`
  - `AuraPlay-Phase14-Master-QA-Checklist.md`
  - `AuraPlay-Phase14-Known-Limitations.md`
- Remaining gate: physical-device QA, Accessibility Inspector/VoiceOver sign-off, App Store archive/upload review, and release screenshots still require a human release pass.
- Why it matters: automated coverage is green, but the app is not truthfully "100% ready to ship" until those device and submission gates are completed.
