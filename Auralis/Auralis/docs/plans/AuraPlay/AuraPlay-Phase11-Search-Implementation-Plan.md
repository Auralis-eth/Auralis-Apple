# AuraPlay Phase 11 — Search

5 Tickets · 8.5 hrs Total Estimate · v1.0 · Updated July 2026

## Phase Purpose

Turn the current AuraPlay search pieces into a coherent user-facing music search experience.

This is no longer a greenfield phase. The app already has a global wallet/NFT/token search surface under `Auralis/Aura/Search`, and AuraPlay already has library text filtering, `MediaItemFilter`, `LibraryItemCell`, `AuraPlaySpotlightIndexer`, `AuraPlayEmbeddingService`, and a root-level semantic search section. Phase 11 should improve and consolidate what exists instead of rebuilding it around the older hypothetical `SearchService` shape.

The boundary is deliberate:

- Global app search remains responsible for accounts, ENS, ERC-20s, NFT tokens, and collections.
- AuraPlay search remains responsible for playable and browsable media inside the active AuraPlay library scope.
- Search UI should live in `MusicFeature` presentation code and consume injected AuraPlay services through `AuraPlayDependencies` / `AuraPlayRootModel`.

## Current Baseline

Already available:

- App-level Search tab / auxiliary surface: `SearchRootView`, `SearchLocalIndex`, `SearchHistoryStore`, `SearchQueryParser`.
- AuraPlay semantic query seam: `AuraPlaySemanticSearching`.
- Live semantic implementation: `AuraPlayEmbeddingService`.
- Spotlight indexing implementation: `AuraPlaySpotlightIndexer`.
- Library query/filter shape: `MediaItemFilter`, `MediaItemMediaTypeFilter`, `MediaItemSort`.
- Reusable library card: `LibraryItemCell` and `LibraryItemCellViewModel`.
- Playback handoff: `AuraPlayPlaybackOrchestrating` and runtime-backed adapter from `MusicAssembly`.
- Existing root UI search affordances: `searchText` local library filtering and the `Semantic Search` section in `AuraPlayEntryView`.

Known mismatch with the older plan:

- There is no single three-tier `SearchService` API with `autocomplete(prefix:)` plus merged `search(query:)` result metadata.
- Semantic search currently returns `[AuraPlaySemanticSearchResult]`, not a merged `SearchResult` containing Spotlight/semantic overlap counts.
- Recent searches should not be a standalone `UserDefaults` one-off if we want consistency with the app's existing SwiftData-backed `SearchHistoryStore` behavior.

## Phase Gate

All five P11-005 scenarios pass with fully mocked search/playback services. The resulting UI must clearly improve the current AuraPlay root search experience without replacing the separate global app search surface.

Hardening status, July 2026:

- `AuraPlaySearchTests` is included in the active `Auralis-Fast` app test plan rather than a separate package-only integration target.
- Focused local verification passed with 7/7 AuraPlay search tests, covering autocomplete, local-plus-semantic merge, stale-query discard, filters, recents, empty query behavior, and search-origin queue windows.
- `AuraPlayEmbeddingService.search` cooperatively checks `Task.checkCancellation()` during the persisted item scan, with a regression test pinning cancellation before stale semantic results can land.
- The April 2026 `SearchService`/three-tier UI wording is superseded for AuraPlay. Do not reintroduce that service shape unless a later architecture decision proves that local matching, semantic search, and optional Spotlight query support need a formal coordinator protocol.
- Search uses the same `MediaItemFilter` data shape as Library. Keep filter UI extraction opportunistic: extract a shared control only if Library and Search start duplicating meaningful UI behavior.

## Ticket Summary

| ID | Title | Type | Priority | Estimate | Depends |
| --- | --- | --- | --- | --- | --- |
| P11-001 | AuraPlay search shell and autocomplete from existing library data | TASK | P0 | 1.5 hrs | P9-001, current `MediaItemQuery` baseline |
| P11-002 | Search results view over local + semantic AuraPlay results | TASK | P0 | 2 hrs | P11-001, current `AuraPlaySemanticSearching` |
| P11-003 | Recent and suggested AuraPlay queries | TASK | P1 | 1.5 hrs | P11-001 |
| P11-004 | Search filters using `MediaItemFilter` | TASK | P1 | 1.5 hrs | P11-002, current Library filter baseline |
| P11-005 | Integration tests for AuraPlay search UI and playback handoff | TASK | P1 | 2 hrs | P11-001 through P11-004 |

## P11-001 — AuraPlay search shell and autocomplete from existing library data

Priority: P0  
Estimate: 1.5 hrs

### Description

Create a real AuraPlay search shell that supersedes the current split between local `searchText` filtering and the separate root-level semantic search section. The first slice should provide a search bar, live local suggestions, and submit behavior while staying inside the Music tab / `MusicFeature` boundary.

This should not use the app-level `SearchRootView`; that surface has different destinations and a different local index. Reuse design patterns where helpful, not code that couples AuraPlay to account/token search.

### Technical Notes

- Prefer a dedicated `AuraPlaySearchView` or search mode inside `LibraryRootView`, depending on what creates the smallest clean patch.
- Autocomplete should be sourced from existing AuraPlay library data: title, artist, collection, and known normalized media fields already used by library filtering.
- Do not introduce the old planned `SearchService` type just to satisfy the ticket name. If a small protocol is useful, keep it AuraPlay-shaped and compatible with `AuraPlaySemanticSearching` / `AuraPlayMediaItemQuerying`.
- Use SwiftUI `.searchable` where it works cleanly with iOS 26 behavior; use a custom suggestion overlay only if `.searchable` cannot express the desired interaction.
- Empty query state should hand off to P11-003 recent/suggested content.
- Register any new accessibility identifiers in `AuraUI/Sources/AuraUI/A11yID.swift` before UI tests depend on them.

### Acceptance Criteria

- Typing produces local autocomplete suggestions without visible lag.
- Suggestions come from the active AuraPlay library scope, not the global app search index.
- Submitting a query transitions to the AuraPlay search results state.
- Empty query shows recent/suggested content rather than a blank result pane.
- The current global Search tab/auxiliary surface behavior remains unchanged.

## P11-002 — Search results view over local + semantic AuraPlay results

Priority: P0  
Estimate: 2 hrs

### Description

Render AuraPlay search results in a music-native result view that combines fast local lexical matches with semantic matches from `AuraPlaySemanticSearching`. Reuse `LibraryItemCell` so search results feel identical to the Library surface.

### Technical Notes

- Local lexical results can come from `AuraPlayMediaItemQuerying` / existing browse snapshots or a small local matcher over active-scope media snapshots.
- Semantic results come from the injected `AuraPlaySemanticSearching` service already wired through `AuraPlayDependencies`.
- Merge by media ID, keeping local exact/prefix matches ahead of fuzzier semantic matches unless semantic score is the only signal.
- Add cancellation discipline: each submitted query cancels the previous Task and uses a generation token before mutating rendered state.
- Update `AuraPlayEmbeddingService.search` if needed so long scans check `Task.isCancelled` or `Task.checkCancellation()` during the item loop.
- Results should render with `LibraryItemCell` / `LibraryItemCellViewModel`, not a new duplicate card.
- Tapping a playable result should call the playback orchestrator with the visible result set as the queue context. If the existing queue-origin type has no search case, add a small explicit search origin instead of overloading library origin silently.
- DEBUG-only diagnostics may show local count, semantic count, overlap count, and semantic score badges. Keep this absent from release builds.
- Empty state should distinguish no matches from an unavailable or not-yet-indexed semantic layer.

### Acceptance Criteria

- Results use the shared Library cell component and visually match Library cards/list rows.
- Local results can appear immediately while semantic search is still resolving.
- Submitting query B while query A is resolving cancels/discards A and only renders B.
- Tapping a playable result starts playback and seeds the queue from the current search result set.
- Non-playable results open detail rather than attempting playback, matching Library behavior.
- DEBUG diagnostics are compiled out of release builds.

## P11-003 — Recent and suggested AuraPlay queries

Priority: P1  
Estimate: 1.5 hrs

### Description

Populate the empty AuraPlay search state with recent music searches and suggested natural-language queries that teach users semantic search exists.

### Technical Notes

- Prefer an AuraPlay-specific history store key/scope. Do not mix AuraPlay music queries into the global `SearchHistoryStore` unless the product decision is to share histories across global and music search.
- Recents should be scoped at least by active account and chain so one wallet's music taste does not leak into another wallet's empty state.
- Persist the last 10 submitted AuraPlay queries, deduplicating case-insensitively and moving repeated queries to the front.
- Suggested queries should showcase semantic search: examples like `lo-fi beats`, `spoken word`, `dark ambient`, `high energy`, or `video tracks`.
- Tapping a recent or suggested query should fill and submit immediately.
- Include clear recent searches.

### Acceptance Criteria

- Submitting a query adds it to the front of the scoped recent list.
- Re-submitting with different case moves the existing item instead of duplicating it.
- The list is capped at 10 entries.
- Suggested queries appear when recents are empty or sparse.
- Clear recent searches removes persisted recent AuraPlay queries for the active scope.

## P11-004 — Search filters using `MediaItemFilter`

Priority: P1  
Estimate: 1.5 hrs

### Description

Add result filtering for chain, media type, and unplayed state using the existing `MediaItemFilter` model so Search and Library stay aligned.

### Technical Notes

- Apply filters after the search merge so relevance order is preserved.
- Use `MediaItemFilter.selectedChains`, `mediaType`, and `unplayedOnly` instead of inventing a search-only filter type.
- Share Library filter UI where practical. If the current Library controls are not extractable yet, first extract a small reusable filter control rather than duplicating behavior.
- Filtering to zero should show a distinct filtered-empty state with a clear-filters action.
- Ensure chain filtering works even though the current AuraPlay scope is usually already chain-scoped; future multi-chain search should not require another model change.

### Acceptance Criteria

- Chain filter narrows results while preserving original relevance order.
- Media type and unplayed filters combine with chain filters as AND conditions.
- Filtered-to-zero state has distinct copy and a one-tap clear-filters action.
- Library and Search use the same filter data shape, and any shared UI is factored once.

## P11-005 — Integration tests for AuraPlay search UI and playback handoff

Priority: P1  
Estimate: 2 hrs

### Description

Validate the assembled AuraPlay search experience with mocks for search, media querying, and playback. These tests should cover UI-layer wiring, not real NaturalLanguage embeddings or CoreSpotlight indexing.

### Technical Notes

- Use Swift Testing where the surface can be exercised at model/view-model level.
- Use XCTest/XCUIAutomation only for true UI automation scenarios.
- Mock `AuraPlaySemanticSearching`, `AuraPlayMediaItemQuerying`, and `AuraPlayPlaybackOrchestrating`.
- Keep real `AuraPlayEmbeddingService` and `AuraPlaySpotlightIndexer` behavior covered by lower-level service tests, not these integration tests.
- If an `AuraPlayIntegrationTests` target still does not exist, either add it deliberately or keep these in the current MusicFeature test target with names/tags that make them easy to split later.

### Required Scenarios

A. Typing a prefix renders local suggestions; submitting transitions to results and calls the semantic search seam.  
B. Tapping a playable result calls playback with the selected item and current result set.  
C. Applying a chain/media/unplayed filter reduces the rendered results and preserves relevance order.  
D. Recent queries update on submit and deduplicate case-insensitively.  
E. Empty query shows recent/suggested content and does not call semantic search.

### Acceptance Criteria

- All five scenarios pass against mocks.
- No test depends on real embedding generation, CoreSpotlight, network discovery, or the live playback engine.
- The suite is deterministic and fast enough for normal CI lanes.
- Accessibility identifiers used by the scenarios are registered in `A11yID`.

## Explicit Non-Goals

- Do not replace the app-level global Search tab.
- Do not move account, ENS, ERC-20, or NFT-token global search into AuraPlay.
- Do not introduce a second router inside AuraPlay.
- Do not rebuild the old planned `SearchService` API unless a separate architecture ticket decides to consolidate AuraPlay lexical, Spotlight, and semantic search behind one service.
- Do not remove the existing semantic service or Spotlight indexer work just because the old ticket text named different types.

## Follow-Up Architecture Decision

After P11 ships, decide whether AuraPlay still needs a formal merged search coordinator. The current likely shape is not the old `SearchService`; it is a small `AuraPlaySearchCoordinating` protocol that composes:

- local library snapshot matching / autocomplete,
- `AuraPlaySemanticSearching`,
- optional Spotlight query support if we add a query client beside the existing indexer,
- result merge metadata for DEBUG diagnostics.

That decision should be based on whether P11-001 and P11-002 can stay simple without it.
