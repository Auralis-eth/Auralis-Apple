# AuraPlay Phase 13 - Intelligence Implementation Plan

6 Tickets · 13 hrs Total Estimate · v1.0 · Updated July 2026

## Phase Purpose

Add music-intelligence features on top of AuraPlay's existing local search, embedding, playlist, playback, and SwiftData boundaries.

This is not an external-AI phase. There are no LLM calls, no provider calls, and no cloud ranking services. The work is a thin product layer over the semantic infrastructure already in the project: `AuraPlayEmbeddingService`, `AuraPlaySemanticSearching`, persisted `AuraPlayMediaEmbedding` rows, `AuraPlaySearchCoordinator`, `MediaItemQueryItem`, and the Phase 8/10 playback orchestration contracts.

The plan below intentionally replaces older April-style names such as `SearchService`, generic `MediaItem`, `PlaybackState`, and `Playlist.aiGenerated`. Current code uses `AuraPlayMediaItem`, `AuraPlayPlaybackPositionState`, `AuraPlayPlaylist.isSmart`, `AuraPlayPlaylist.smartQueryData`, `AuraPlayPlaylistService`, and `AuraPlayQueueOriginPresentation`.

## Current Baseline

Already available:

- Semantic search seam: `AuraPlaySemanticSearching.search(query:in:limit:minimumScore:)`.
- Live embedding service: `AuraPlayEmbeddingService`, backed by `TextEmbeddingProviding` and `NaturalLanguageTextEmbeddingProvider`.
- Persisted vectors: `AuraPlayMediaEmbedding` with `mediaItemID`, `vectorData`, `embeddingModelVersion`, `sourceFingerprint`, and `indexedAt`.
- Search merge utilities: `AuraPlaySearchCoordinator`, `AuraPlaySearchResult`, and `AuraPlaySearchDiagnostics`.
- Library query rows: `MediaItemQueryItem`, `MediaItemFilter`, `MediaItemQueryContext`, and `AuraPlayMediaItemService`.
- Reusable library row/card presentation: `LibraryItemCell` and `LibraryItemCellViewModel`.
- Playlist persistence: `AuraPlayPlaylist`, `AuraPlayPlaylistItem`, and `AuraPlayPlaylistService`.
- Playback orchestration presentation contracts: `AuraPlayPlaybackOrchestrating`, `AuraPlayQueueWindow`, and `AuraPlayQueueOriginPresentation`.
- Runtime queue implementation: app-target `QueueOrigin` and `ShuffleCoordinator` under `Auralis/MusicApp/AuraPlay/Services/`.
- Resume threshold logic: `AuraPlayPlaybackPositionStateSnapshot.isResumable` already uses the 5-second near-start / near-end rule.

Known gaps this phase must treat honestly:

- There is no `SearchService.semanticSearch(query:)`; use `AuraPlaySemanticSearching` and, where necessary, add small AuraPlay-shaped helpers beside `AuraPlaySearchCoordinator`.
- `NaturalLanguageTextEmbeddingProvider` currently uses English sentence/word embeddings, not the user's current locale. The availability gate should therefore probe the injected provider the app actually uses rather than assume arbitrary device-language coverage.
- `AuraPlayPlaybackPositionState` does not yet persist chain, contract, token ID, play count, or completed count. Smart Resume and Smart Shuffle cannot assume those fields exist.
- There is no Persistent History tombstone implementation in the current source. If tombstone recovery is required, Phase 13 must add a small explicit AuraPlay-owned tombstone snapshot or update the playback-state schema and deletion path deliberately.
- `AuraPlayPlaylist.isSmart` and `smartQueryData` exist; there is no `aiGenerated` field. Generated playlists should use `isSmart = true` plus encoded smart-query metadata.
- The public queue origin already has `.search(query:)`; it does not yet have `.moreLikeThis(sourceID:)` or `.generatedPlaylist(prompt:)`.

## Phase Gate

All six P13-005 scenarios pass with deterministic vectors and in-memory SwiftData. The implementation must prove that Playlist Playground and More Like This make zero network calls during ranking/generation, and that unsupported embedding availability hides semantic-dependent entry points without breaking normal AuraPlay search and library browsing.

## Ticket Summary

| ID | Title | Type | Priority | Estimate | Depends |
| --- | --- | --- | --- | --- | --- |
| P13-001 | Playlist Playground over `AuraPlaySemanticSearching` | TASK | P1 | 3 hrs | P11 search, P9 playlists, P13-006 |
| P13-002 | More Like This from stored `AuraPlayMediaEmbedding` vectors | TASK | P1 | 2 hrs | P11 search, P10 context menus, P13-006 |
| P13-003 | Smart Resume from explicit AuraPlay tombstones | TASK | P1 | 2.5 hrs | P8 playback persistence, Phase 5 sync reconciliation |
| P13-004 | Smart Shuffle weighting over playback history | TASK | P2 | 2 hrs | P8 shuffle, P10 player controls, playback-history schema slice |
| P13-005 | Integration tests for intelligence features | TASK | P1 | 2.5 hrs | P13-001 through P13-004 |
| P13-006 | Embedding availability gate | TASK | P1 | 1 hr | Current `TextEmbeddingProviding` / `AuraPlayEmbeddingService` |

## P13-001 - Playlist Playground over `AuraPlaySemanticSearching`

Priority: P1  
Estimate: 3 hrs

### Description

Add a prompt-based playlist generator inside AuraPlay that turns a natural-language music description into a preview list by calling the existing semantic search seam. The feature should feel intelligent, but the implementation is deliberately local and boring: embed the prompt, rank scoped AuraPlay media, preview the candidates, and save them through the existing playlist actor.

### Technical Notes

- Add the entry point in the AuraPlay Library/Search area, not the global app Search surface. This belongs to `MusicFeature` presentation and consumes `AuraPlayDependencies`.
- Use `AuraPlaySemanticSearching.search(query:in:limit:minimumScore:)` with the active `AuraPlayLibraryScope`.
- Fetch a larger candidate pool than the final playlist size, for example 60 results, then materialize a preview capped at 25.
- Use `MediaItemQueryItem` as the preview row model after resolving semantic result IDs through `AuraPlayMediaItemService` or a focused lookup helper.
- Reuse `LibraryItemCell` / `LibraryItemCellViewModel` for the preview.
- Save through `AuraPlayPlaylistService`, but extend the service deliberately if bulk creation is needed. Avoid looping from the view if that scatters playlist-ordering logic.
- Generated playlists should be `AuraPlayPlaylist(isSmart: true, smartQueryData: encoded metadata)`, not `aiGenerated = true`.
- Suggested smart metadata shape: original prompt, result IDs in ranked order, minimum score, created date, and model version if available.
- Regenerate should not re-run a cloud model. Use the larger semantic candidate pool and sample locally with a score-biased weighted draw that excludes the immediately previous preview when the pool is large enough.
- If fewer than 5 candidates clear the threshold, show broaden-your-prompt guidance and do not save a nearly empty playlist silently.
- Copy should be explicit and accurate: "Generated on this device from your AuraPlay library." Do not imply Apple Intelligence or an LLM.
- Register any new controls and empty states in `AuraUI/Sources/AuraUI/A11yID.swift` before UI tests depend on them.

### Acceptance Criteria

- Submitting a prompt calls `AuraPlaySemanticSearching.search` and renders up to 25 preview rows.
- Saving creates an `AuraPlayPlaylist` with `isSmart = true` and adds `AuraPlayPlaylistItem` rows in the preview order.
- Smart-query metadata is persisted in `smartQueryData` and can be decoded by tests.
- Prompts with fewer than 5 qualifying results show broaden-your-prompt guidance and do not save.
- Regenerate produces a different preview from the immediately previous generation when the candidate pool is large enough; small pools use a documented reshuffle fallback.
- The entry point is absent when P13-006 reports embeddings unavailable.
- Generation performs no network requests.

## P13-002 - More Like This from stored `AuraPlayMediaEmbedding` vectors

Priority: P1  
Estimate: 2 hrs

### Description

Add a media-item context action that finds similar AuraPlay items by comparing the selected item's stored vector against other persisted `AuraPlayMediaEmbedding` rows in the same library scope.

Unlike Playlist Playground, this does not embed user text. It starts from an existing `AuraPlayMediaItem.sourceNFTID`, reads that item's stored vector, computes cosine similarity against sibling vectors, excludes the source item, and presents the ranked results.

### Technical Notes

- Add a service/protocol shaped for the actual model, for example `AuraPlayRecommendationProviding.moreLikeThis(mediaItemID:in:limit:)`.
- Implement the live service in `MusicFeature` or the app target only if it needs app-only collaborators. It should operate on `AuraPlayMediaEmbedding` and `AuraPlayMediaItem` in the AuraPlay model container.
- Reuse the cosine-similarity logic already used by `AuraPlayEmbeddingService`. If extraction is needed, move the math into a small shared helper such as `AuraPlayEmbeddingSimilarity` rather than copying loops into another service.
- Hide the context action when the selected item has no current embedding for the active model version.
- Present results in a sheet using `LibraryItemCell` / `LibraryItemCellViewModel`.
- Add `AuraPlayQueueOriginPresentation.moreLikeThis(sourceID:)` and the app-target `QueueOrigin.moreLikeThis(sourceID:)` rather than overloading `.search(query:)`.
- `Play All` should call `AuraPlayPlaybackOrchestrating.play(item:queue:startAt:origin:)` with an `AuraPlayQueueWindow` built from the visible similar results.
- `Save as Playlist` should reuse the same playlist materialization helper created for P13-001.
- Use named recommendation thresholds: strict `0.72` first, then retry once at relaxed `0.60` only when the strict pass yields fewer than three results.

### Acceptance Criteria

- `moreLikeThis` returns ranked results excluding the source media ID.
- The context menu action is hidden when no stored embedding exists for the source item.
- Threshold relaxation, if implemented, only applies when the strict pass yields fewer than 3 results.
- `Play All` queues the visible results with `.moreLikeThis(sourceID:)`.
- `Save as Playlist` reuses the same playlist materialization path as Playlist Playground.
- The recommendation pass performs no network requests and does not invoke `TextEmbeddingProviding.vector(for:)` for a text prompt.

## P13-003 - Smart Resume from explicit AuraPlay tombstones

Priority: P1  
Estimate: 2.5 hrs

### Description

Preserve meaningful playback progress when a playable NFT temporarily disappears from a wallet and later returns with the same on-chain identity.

The current code does not have persistent-history tombstones or deletion-preserved chain/contract/token fields on `AuraPlayPlaybackPositionState`, so this ticket must add the missing AuraPlay-owned recovery contract explicitly.

### Technical Notes

- Add a small persisted tombstone model or schema extension, for example `AuraPlayPlaybackPositionTombstone` with media ID, account address, chain, contract address, token ID, position, duration, last played date, captured date, and optional completed date.
- Capture tombstones when sync reconciliation removes or deactivates an `AuraPlayMediaItem` that has a resumable `AuraPlayPlaybackPositionStateSnapshot`.
- Match restoration only by exact on-chain identity: account scope where relevant, chain, normalized contract address or Solana mint equivalent, and token ID/source NFT identity. Do not use semantic similarity for resume recovery.
- Run `SmartResumeCoordinator` after `NFTSyncCoordinator` completes reconciliation and media rows have been upserted.
- Restore by writing a new `AuraPlayPlaybackPositionState` for the returned media row through `AuraPlayPlaybackPositionStateService`.
- Reuse `AuraPlayPlaybackPositionStateSnapshot.isResumable` for the near-start/near-end threshold.
- Keep the recency window narrow, for example 7 days from `lastPlayedAt`.
- Log at `.info` through `AuraPlayLogging`; no user-facing UI is required for normal restoration.
- Delete or mark consumed tombstones after a successful restore so the same position is not repeatedly revived.

### Acceptance Criteria

- A resumable tombstone restores position when the same on-chain token returns as a new AuraPlay media row.
- A tombstone whose token never reappears produces no restore attempt and no surfaced error.
- Non-resumable near-start or near-end progress is not tombstoned/restored.
- Tombstones older than the recency window are ignored.
- Restoration is silent in UI, and the mini-player/library resume behavior reads the restored position normally.

## P13-004 - Smart Shuffle weighting over playback history

Priority: P2  
Estimate: 2 hrs

### Description

Add an optional shuffle strategy that biases playback away from very recently played items and toward never-played or under-played items, while keeping the existing plain shuffle path unchanged.

### Technical Notes

- Keep the existing public shuffle mode compatible (`off/on`) and layer Smart Shuffle as an optional Settings-backed strategy inside the same coordinator lifecycle.
- `AuraPlayPlaybackPositionState` now persists `playCount`; Smart Shuffle may use play count plus `lastPlayedAt` and never-played status.
- Put the weighting algorithm in a pure, tested type such as `SmartShuffleWeighting` so it can be exercised without live audio/video engines.
- Inputs should be queue entries plus playback-history snapshots keyed by media ID.
- Never-played items should receive the highest base weight.
- Items played in the last 24 hours should receive a strong downweight.
- Weighted random selection should compute a full order when shuffle mode is enabled, matching the existing `ShuffleCoordinator` lifecycle.
- Repeat-all should rebuild a fresh smart order the same way plain shuffle rebuilds a fresh order.
- Settings/UI copy should call this "Smart Shuffle" only when the mode is actually active; normal shuffle remains available.

### Acceptance Criteria

- With Smart Shuffle enabled, deterministic seeded trials favor never-played items near the front of a large fixture queue.
- With Smart Shuffle disabled or plain shuffle selected, existing shuffle behavior remains unchanged.
- Recently played items have measurably lower selection probability than equivalent unplayed items.
- Repeat-all rebuilds a new smart order per loop.
- Tests cover duplicate queue entries by entry ID and media ID so duplicate-safe Phase 8 behavior is preserved.

## P13-005 - Integration tests for intelligence features

Priority: P1  
Estimate: 2.5 hrs

### Description

Validate the Phase 13 features with deterministic fixtures, in-memory SwiftData, mock embedding providers, and mocked playback/network seams.

These tests should live where Xcode actually runs them today. The app-hosted `AuralisTests` lane already contains AuraPlay search and embedding tests; package-local tests are fine only if the active scheme/test plan runs them reliably.

### Technical Notes

- Prefer Swift Testing for model/service/coordinator scenarios.
- Use XCUIAutomation only for end-to-end UI smoke coverage that cannot be verified at model level.
- Use deterministic `TextEmbeddingProviding` fixtures; do not depend on live `NLEmbedding` output in CI.
- Reuse `AuralisTestSupport` and existing AuraPlay fixture helpers where practical. Add explicit embedding fixtures only if current fixture coverage cannot express the needed vectors.
- Add a zero-network assertion around Playlist Playground and More Like This by injecting services/clients that fail on URL access.

### Required Scenarios

A. Playlist Playground turns a fixture prompt into the expected preview set and saves an `isSmart` playlist with ordered items and decodable `smartQueryData`.  
B. Regenerate changes the preview for a large candidate pool and uses the fallback path for a small pool.  
C. More Like This from a fixture media item returns expected similar items, excludes itself, and hides the action when the source has no embedding.  
D. Smart Resume restores a tombstoned playback position when the exact token identity reappears.  
E. Smart Resume ignores stale and non-resumable tombstones.  
F. Smart Shuffle weighting favors unplayed/recently-unplayed items over a large deterministic trial count while plain shuffle remains unchanged.

### Acceptance Criteria

- All six scenarios pass deterministically across repeated local runs.
- No test depends on live `NLEmbedding` inference, CoreSpotlight indexing, provider networking, or real playback engines.
- The suite remains fast enough for normal CI lanes.
- The original "five consecutive CI runs" gate requires CI history, not a local Xcode run. Local validation can only prove the selected deterministic cases pass in the active test plan.
- Any UI-facing controls used by tests have registered `A11yID` values.

## P13-006 - Embedding availability gate

Priority: P1  
Estimate: 1 hr

### Description

Add a single injected availability check for semantic-dependent AuraPlay features. Playlist Playground and More Like This should be absent when embeddings are unavailable; normal library browsing, lexical search, filters, playlists, and playback remain available.

### Technical Notes

- Shape the seam around the current implementation, for example `AuraPlayEmbeddingAvailabilityProviding` with cached `availability` / `isAvailable`.
- The live provider should probe the same `TextEmbeddingProviding` used by `AuraPlayEmbeddingService`, for example by requesting a vector for a stable non-empty phrase such as `music`. This is more accurate for this codebase than checking an arbitrary device language API directly.
- Cache the result at launch/composition time in `MusicAssembly`, and provide a way to invalidate/recheck if the embedding provider or relevant language setting changes later.
- For tests, inject a provider that returns nil vectors to simulate unavailable embeddings.
- When unavailable, hide Playlist Playground and More Like This entry points. Show one explanatory Settings/Search or AuraPlay settings note rather than repeated inline failures.
- Do not gate literal AuraPlay search, `AuraPlaySearchCoordinator.localMatches`, Spotlight indexing, playlist CRUD, or playback.

### Acceptance Criteria

- Availability returns true with a vector-producing fixture provider and false with a nil-returning provider.
- The result is cached and not recomputed on every view render.
- Playlist Playground and More Like This are absent when unavailable.
- Plain AuraPlay local search and library filters remain functional when unavailable.
- Tests cover an availability change/recheck without relaunching the whole app shell.

## Explicit Non-Goals

- Do not add external LLM calls or network ranking services.
- Do not move global app search into AuraPlay.
- Do not replace `AuraPlaySemanticSearching` with a new generic `SearchService`.
- Do not replace the Phase 8 playback orchestrator or add a second queue authority.
- Do not use content-similarity guesses for Smart Resume. Resume recovery is exact token identity only.
- Do not introduce smart playlist auto-refresh semantics in this phase. Generated playlists are saved snapshots unless a later phase deliberately defines live smart playlists.

## Implementation Order

1. P13-006 first, so semantic entry points can depend on one gate.
2. P13-001 and P13-002 next, sharing playlist materialization and vector/similarity helpers where useful.
3. P13-003 after the tombstone schema/coordinator shape is agreed.
4. P13-004 after deciding whether this phase adds play counts or ships recency/unplayed weighting only.
5. P13-005 continuously, with fixture vectors and zero-network assertions added alongside each feature slice.
