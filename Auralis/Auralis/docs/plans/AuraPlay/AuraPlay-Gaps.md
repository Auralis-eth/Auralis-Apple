# AuraPlay — Gaps

This is the single living gap log for the AuraPlay rebuild. Each entry names something that should exist for the product to be complete but is **not yet in code**. Each entry says what it should be, where it should live, and why it matters.

This file lists open gaps only. When a gap closes, delete its entry (see "How To Use This File"). Anything actually shipped lives in `AuraPlay-Status.md`; do not duplicate it here.

## Phase 1 Gaps

### CarPlay audio entitlement is missing

- Expected: `com.apple.developer.carplay-audio` declared in `Auralis/Auralis/Auralis.entitlements`.
- Actual: the entitlements file is an empty dict.
- Why it matters: blocks future CarPlay work and any provisioning that expects the entitlement to already be declared. Adding it also requires a matching provisioning profile, so close it with a signing decision rather than a bare edit.

### `NSMotionUsageDescription` is missing

- Expected: motion usage string in `Auralis/Auralis/Info.plist` to support motion-triggered playlist behavior.
- Actual: not present.
- Why it matters: only matters if motion-triggered playlist switching is still on the roadmap. If that feature has been dropped, close the gap with an explicit decision instead of code.

### Not every planned secret flows through the build config

- Expected: the gateway secrets the roadmap anticipates — a configurable IPFS gateway URL and Arweave gateway URL — declared in `Secrets.local.xcconfig.template` and mirrored into `Info.plist`, alongside the API keys.
- Actual: `AURALIS_ALCHEMY_API_KEY`, `AURALIS_HELIUS_API_KEY`, and `AURALIS_WALLETCONNECT_PROJECT_ID` are declared. There is no build-config slot for a configurable IPFS or Arweave gateway URL.
- Why it matters: gateway host lists are currently code-owned; any deployment that needs to point at a different IPFS/Arweave gateway has nowhere to register the value cleanly.

### No typed `AppConfig` access layer

- Expected: a single `AppConfig` type that reads `Bundle.main.infoDictionary` and surfaces a clear developer-facing error when a required key is missing.
- Actual: callers read `Bundle.main.infoDictionary` directly; `AuraPlayModuleConfiguration.live(infoDictionary:)` only validates the music-tab bundle contract.
- Why it matters: missing keys fail silently as empty strings instead of surfacing a clear error at boot.

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
- Why it matters: force-unwrap regressions slip in without lint signal; long files and types are not flagged. Enabling these will surface a backlog of existing violations, so close it with a cleanup pass rather than a config flip alone.

### The ticketed-TODO rule is AuraPlay-only

- Expected: every part of the codebase requires TODOs to reference a ticket ID.
- Actual: `auraplay_ticketed_todo` only applies under `Auralis/MusicApp/AuraPlay`. Elsewhere, untagged TODOs are accepted.
- Why it matters: the rest of the codebase can accumulate untracked TODO debt.

### CI jobs are not split

- Expected: separate `lint`, `build`, and `test` jobs so failures show up as distinct checks.
- Actual: `auralis-ci.yml` runs lint/build/test steps in one job.
- Why it matters: small workflow cleanliness gap, no functional gap.

### No secrets injection in CI

- Expected: CI writes `Secrets.local.xcconfig` from GitHub Secrets so the build sees real keys.
- Actual: the workflow does not touch `Secrets.local.xcconfig`. The build compiles with the placeholder empty keys.
- Why it matters: any test that actually needs a live API key will silently see an empty string.

### No DerivedData / SPM cache and no xcresult artifact upload

- Expected: `actions/cache` on `DerivedData` and the SPM cache, plus an `xcresult` artifact upload on failure.
- Actual: neither is wired.
- Why it matters: CI is slower than necessary, and failed-test triage requires re-running locally rather than downloading the result bundle.

### No top-level README or CONTRIBUTING

- Expected: `README.md` and `CONTRIBUTING.md` at the repo root, plus a `docs/decisions/INDEX.md` listing all ADRs.
- Actual: none of the three exist. ADRs are discoverable only by directory listing.
- Why it matters: a new engineer cannot follow a single onboarding doc to a working build.

## Phase 2 Gaps

### AuraPlay-owned wallet service is not built

- Expected: an `@ModelActor` wallet service in `MusicFeature` exposing upsert / fetchAll / fetchActive / deactivate / deleteAll operations against the AuraPlay read path.
- Actual: the shared `EOAccount` `@Model` exists in `AuralisPrimaryPersistence` (keyed by `address`, with a cascading `nfts: [NFT]` relationship and per-chain AuraPlay sync metadata). AuraPlay carries wallet scope through `AuraPlayLibraryScope` and the sync service mutates `EOAccount` directly. There is no AuraPlay-owned wallet service surface.
- Why it matters: AuraPlay does not need a second wallet model — it needs a deliberate decision on whether a wallet service should live in `MusicFeature` over the shared model, or whether shell-level account services should be extended for AuraPlay's needs (ENS storage, scope history, multi-wallet UI). A `WalletService.deleteAll()` is also the natural home for the CoreSpotlight domain purge described below.

### `AuraPlayMediaItem` has no user-override fields or display fallbacks

- Expected: `overrideTitle`, `overrideCreator`, `overrideArtworkURL`, `overrideGenre` fields written only by user action, plus computed `displayTitle` / `displayCreator` / `displayArtworkURL` properties that prefer the override and fall back to the sync-owned field. A typed `MediaItemOverride` value plus a service-level `applyUserOverride(_:id:)` mutation path that also re-indexes the affected item into CoreSpotlight.
- Actual: `AuraPlayMediaItem` has no override-shaped fields and no override mutation path.
- Why it matters: user-curated metadata edits cannot survive a sync because every field is treated as sync-owned.

### Tier 1 trie autocomplete is not built

- Expected: an in-memory trie (`TrieNode` with `children: [Character: TrieNode]` + `mediaItemIDs: Set<String>`, an immutable `Trie` value, an `@Observable TrieIndex`, and a `TrieBuilder` `@ModelActor` that rebuilds after each sync via `NLTokenizer`) backing a synchronous `autocomplete(prefix:) -> [String]`.
- Actual: Tier 2 (CoreSpotlight, `AuraPlaySpotlightIndexer`) and Tier 3 (semantic embeddings, `AuraPlayEmbeddingService` + `AuraPlayMediaEmbedding`) both exist and are wired through `MusicAssembly`/`NFTSyncCoordinator`. There is no trie type and no synchronous autocomplete path.
- Why it matters: autocomplete-as-you-type has no sub-millisecond local index; the existing tiers are async query paths, not prefix completion.

### Unified `SearchService` facade is not built

- Expected: one `SearchService` as the single public search API exposing `autocomplete(prefix:)` and `search(query:) async -> SearchResult`, running Tier 2 and Tier 3 in parallel, blending scores (spotlight × 0.55 + semantic × 0.45 + overlap boost), deduplicating, and returning a `SearchResult` (`ids`, `spotlightCount`, `semanticCount`, `overlapCount`) so debug overlays can inspect tier participation.
- Actual: the indexer and the semantic search live as separate pieces; there is no `SearchService` facade, no blend/merge step, and no `SearchResult` result type. Callers would have to assemble the tiers themselves.
- Why it matters: search UI work cannot depend on a single entry point or a blended, ranked result until the facade lands.

### Embedding fixtures for deterministic semantic tests are not built

- Expected: an `EmbeddingFixtures` test helper that ships pre-computed Float32 vectors for the canonical seeded media items so semantic-search assertions can compare against known scores without re-running `NLEmbedding` in every test.
- Actual: `AuraPlayEmbeddingService` exists and is exercised by `AuraPlayIndexingAndEmbeddingTests`, but there is no stable pre-computed fixture corpus.
- Why it matters: semantic-search tests will drift the moment Apple updates the embedding model unless they can compare against a fixed corpus.

### Derived search/embedding rows are not purged on deletion

- Expected: deleting an `AuraPlayMediaItem` removes its derived semantic-index row and its CoreSpotlight item; dropping a wallet calls `deleteAll(domain: "com.auraplay.media")` so the scope's CoreSpotlight footprint is purged.
- Actual: `AuraPlayMediaEmbedding` is a standalone row keyed by `mediaItemID` with no cascade inverse to `AuraPlayMediaItem`. `AuraPlaySpotlightIndexer.indexItems` is wired on upsert, but there is no delete/purge call site (and no wallet service to host the domain-wide purge).
- Why it matters: media-item and wallet deletion will leave orphaned semantic rows and stale CoreSpotlight results.

### No dedicated AuraPlay seeder/fixtures package

- Expected: a test-only `AuraPlayTestSupport` package holding a tiered seeder (`.minimal`, `.standard`, `.large`) with deterministic IDs and fixed-epoch dates, plus a primed CoreSpotlight mock index and the `EmbeddingFixtures` corpus, never linked into the app target.
- Actual: `AuraPlayLibrarySeed` in the `MusicFeatureTests` target already provides `.minimal`/`.standard`/`.large` tiers, but it lives inside the test target (not a shared package) and ships no Spotlight or embedding fixtures.
- Why it matters: previews and other test targets cannot share the one stable dataset, and semantic/Spotlight tests still lack fixture surfaces.

### No cross-entity integration suite

- Expected: a Swift Testing suite that exercises the full model graph end-to-end against an in-memory container — cascade delete from wallet through media item (including the CoreSpotlight purge), playlist integrity after media-item deletion, recently-played ordering, unplayed query, user-override round-trip, the search round-trip across tiers, tombstone retrieval, and uniqueness-constraint behavior.
- Actual: focused MusicFeature tests cover schema registration, container boot, indexing/embedding, and persisted-library preference, but no single suite exercises the whole graph end-to-end.
- Why it matters: as more models land, this is where the safety net needs to grow.

### `AuraPlayIntegrationTests` target does not exist

- Expected: a separate integration-test target so end-to-end scenarios can be filtered out of fast CI lanes and run as a distinct job.
- Actual: there is no such target; CI runs all `MusicFeatureTests` together.
- Why it matters: small organizational gap — flag if integration runtimes start dominating CI minutes.

## Phase 6 Gaps

### Physical-device audio-engine release gates are not signed off

- Expected: completed physical-device QA from `AuraPlay-Physical-Device-QA-Suite.md` for the audio engine.
- Actual: the package infrastructure and host UI wiring are implemented — Settings, Now Playing, and the mini player expose EQ, custom 10-band EQ, normalization, AutoMix, route, cache/offline, buffering/download progress, recovery, transition status, and transient typed playback warnings.
- Why it matters: package readiness and UI wiring are not the same as a shippable playback experience. AirPods, interruptions, Lock Screen, background, audible gaplessness, poor-network buffering, offline launch, and battery behavior need real hardware before the phase can close.

## Phase 9/10 Gaps

### Snapshot baselines render on the macOS host, not an iOS simulator

- Expected: eventually, an iOS-simulator snapshot lane so baselines match shipping pixels.
- Actual: `LibraryAndPlayerSnapshotTests` renders through `NSHostingView` on macOS because app-hosted tests crash under the current Xcode beta and `swift test` builds for the host. The suite is deterministic and stable, but the pixels are macOS pixels.
- Why it matters: a future iOS snapshot lane requires re-recording all baselines; do not mix baselines from both platforms.

### Library populates only when network discovery is available

- Context: `NFTSyncCoordinator` (network discovery) is the single authoritative writer of `AuraPlayMediaItem`.
- Residual: when discovery is unavailable (e.g. missing Alchemy/Helius keys → `NoOpAuraPlayNFTDiscoverySyncService`), nothing projects the already-downloaded local `NFT` inventory into `AuraPlayMediaItem`, so the library can be empty even though local NFT rows exist. This is an accepted tradeoff (the local inventory needs the same keys to populate anyway).
- Follow-up if needed: fall back to a non-destructive local projection only when discovery is the no-op service, or fold video/animation-URL handling into the local projection so it is no longer audio-only.

### Physical-device QA and manual accessibility audit are outstanding

- Expected: the device QA suite in `AuraPlay-Physical-Device-QA-Suite.md` executed on hardware (PiP, AirPlay, subtitles, speed, routes, interruptions), plus an Accessibility Inspector pass over Library and Player.
- Actual: everything code-side is automated-tested; these two gates need a human with a device.
- Why it matters: they are the last release gates for Phases 9/10.

## Phase 11 (Search) Gaps

### Assistant result-quality evaluation is a seed, not real coverage

- Expected: a meaningful evaluation corpus for `SearchAssistantService` that scores real result relevance (precision/recall over representative queries), not just structural round-trips.
- Actual: `SearchAssistantEvaluationTests` is a deliberately small seed whose `subject(from:)` returns a hand-rolled fixture stub, so it scores harness math, not the real assistant. It does not drive `SearchAssistantService` / the live `SpotlightSearchTool` pipeline. The on-device model reports `.available` on the physical iOS 27 test device, so a model-driven evaluation is runnable — the blocker is the missing work: point `subject` at the real service against a seeded CoreSpotlight domain, grow the corpus to representative per-domain queries, and keep it out of the fast lane (live LLM + async Spotlight indexing is nondeterministic).
- Why it matters: until the eval drives the real pipeline, assistant result quality is unverified even though the path runs.

## Phase 14 Gaps

### Manual release gates are not signed off

- Expected: the release gates described in `AuraPlay-Phase14-Settings-Accessibility-Hardening-Plan.md`.
- Actual: the Phase 14 artifacts (accessibility findings, error-presentation audit, App Review checklist, master QA checklist, known-limitations notes) all exist, and automated coverage is green.
- Remaining gate: physical-device QA, Accessibility Inspector/VoiceOver sign-off, App Store archive/upload review, and release screenshots still require a human release pass.
- Why it matters: the app is not truthfully "100% ready to ship" until those device and submission gates are completed.

## How To Use This File

- Pick gaps off this list deliberately when a downstream phase needs them.
- When a gap is closed, **delete its entry** and add a one-line note in `AuraPlay-Status.md` reflecting the new reality. Do not leave "RESOLVED" narratives here — this file lists only what is still open.
- Each new phase should add its own gap entries here under a `## Phase N Gaps` heading. Do not start a separate file per phase.
