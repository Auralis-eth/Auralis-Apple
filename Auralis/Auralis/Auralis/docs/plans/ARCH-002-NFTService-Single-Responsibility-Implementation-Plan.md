# ARCH-002: Split `NFTService` Into Focused, Single-Responsibility Types

## Goal

Turn `NFTService` from a multi-job manager into a thin refresh coordinator.

After this change:

- fetching raw inventory is its own concern
- metadata enrichment is its own concern
- SwiftData persistence and cleanup are its own concern
- freshness and staleness logic are their own concern
- the coordinator sequences those pieces and exposes shell-friendly state

The target is not “more files for the sake of it.” The target is explicit seams, better tests, and less accidental coupling between network, transformation, persistence, and UI state.

## Current State

`NFTService.swift` currently contains all of the following in one file and one top-level service:

- refresh orchestration and in-flight cancellation
- event recording
- raw NFT fetch delegation
- metadata decoding and patch application
- deduplication
- persistence snapshot creation
- SwiftData persistence actor logic
- stale NFT cleanup
- tracked-count synchronization
- orphaned shared-model cleanup
- refresh freshness bookkeeping for UI
- provider-failure presentation helpers

That shape makes the class hard to reason about because every change has to tiptoe through several layers at once.

### Concrete pressure points

- `fetchAllNFTs(...)` sequences fetching, transformation, persistence, cleanup, event recording, and refresh-state updates in one method.
- `prepareFetchedNFTs(...)` mutates provider models, applies metadata patches, reapplies scope, and deduplicates.
- `prepareMetadataPatches(...)` is effectively a metadata use case already, but it lives as a private helper inside the coordinator.
- `NFTRefreshPersistenceStore` is a real persistence boundary, but it is buried inside `NFTService.swift` and hidden behind persistence snapshot plumbing that the coordinator also owns.
- freshness state (`successfulRefreshTimestamps`, `refreshTTL`, `lastSuccessfulRefreshAt`) lives beside orchestration state (`inFlightRefreshTask`, `refreshPhase`) even though those concerns change for different reasons.

## Target Architecture

Keep one shell-scoped orchestrator, but make it sequence narrower collaborators.

### Proposed runtime shape

- `NFTRefreshCoordinator`
  - public API that current shell code can call
  - owns in-flight refresh cancellation and phase publishing
  - records refresh events
  - sequences fetch -> metadata -> persist -> cleanup -> refresh-state update
- `FetchNFTInventoryUseCase`
  - calls the network provider/fetcher
  - returns raw provider inventory for a requested wallet and chain
- `PrepareNFTMetadataUseCase`
  - applies refresh scope
  - computes metadata patches
  - applies metadata enrichment
  - deduplicates by NFT id
- `PersistNFTInventoryUseCase`
  - owns SwiftData writes through the existing `@ModelActor` persistence path
  - persists current inventory
  - cleans up stale inventory after a completed full refresh
  - synchronizes tracked counts and prunes orphaned shared models
- `NFTRefreshStateComputer`
  - computes freshness/staleness from successful refresh timestamps and TTL
  - centralizes “when is content fresh enough?” logic

### Boundary rule

The coordinator should deal in feature-level inputs and outputs:

- refresh request
- refresh phase
- provider failure
- last successful refresh timestamp

It should not know how metadata is decoded, how SwiftData upserts work, or how orphaned shared models are pruned.

## Recommended Type Split

### 1. `FetchNFTInventoryUseCase`

Suggested responsibility:

- wrap `any NFTFetching`
- fetch all inventory for a scope
- return fetched NFTs and fetch-completion information needed by the coordinator

Suggested output shape:

- `FetchedNFTInventory`
  - `nfts: [NFT]`
  - `didCompleteFullRefresh: Bool`

Why this shape:

- the coordinator currently infers full-refresh completion by peeking into fetcher pagination state
- that detail belongs next to the fetch boundary, not spread across orchestration code

### 2. `PrepareNFTMetadataUseCase`

Suggested responsibility:

- transform fetched NFTs into refresh-ready inventory
- apply account/chain scope consistently
- decode inline/base64 metadata
- derive metadata patches from token URI and raw metadata
- deduplicate repeated ids

Suggested input/output:

- input:
  - `fetchedNFTs`
  - `accountAddress`
  - `chain`
- output:
  - `PreparedNFTInventory`
    - `nfts: [NFT]`
    - optionally `persistableSnapshots: [NFTRefreshPersistenceSnapshot]` if snapshot creation moves here

Important design choice:

Do not leave half the metadata pipeline in the coordinator. Either this use case owns the preparation pass end-to-end, or it becomes another fake seam.

### 3. `PersistNFTInventoryUseCase`

Suggested responsibility:

- persist current inventory for one account/chain scope
- optionally perform stale cleanup when a full refresh has completed
- keep the `@ModelActor` store as the write boundary

Suggested public API:

- `persist(_ inventory: PreparedNFTInventory, accountAddress: String, chain: Chain, modelContext: ModelContext, shouldCleanupStaleInventory: Bool) async throws`

Internals that should move under this use case:

- `NFTRefreshPersistenceStore`
- persistence scope snapshot types
- model upsert/merge logic
- stale NFT cleanup
- tracked count synchronization
- orphaned shared-model pruning
- persistence snapshot creation if snapshots remain the persistence contract

This keeps SwiftData-specific complexity out of the coordinator.

### 4. `NFTRefreshStateComputer`

Suggested responsibility:

- store or compute:
  - last successful refresh per account/chain scope
  - whether content is fresh for a given TTL
  - whether a new refresh should be considered stale/degraded

Suggested shape:

- a small value type plus stored state on the coordinator, or
- a dedicated reference type injected into the coordinator if multiple features need the same freshness model

Recommendation:

Start with a narrow dedicated type used only by the coordinator. Do not prematurely turn freshness logic into app-global shared state.

## Naming Recommendation

Use a staged rename instead of renaming everything in one jump.

### Phase 1 names

- keep `NFTService` as the public shell-facing type
- introduce:
  - `LiveFetchNFTInventoryUseCase`
  - `LivePrepareNFTMetadataUseCase`
  - `LivePersistNFTInventoryUseCase`
  - `NFTRefreshStateComputer`

### Phase 2 names

Once the orchestration-only shape is stable, consider renaming `NFTService` to `NFTRefreshCoordinator` and leave:

- `typealias NFTService = NFTRefreshCoordinator`

temporarily if downstream churn needs to stay low.

That avoids mixing architecture cleanup with a large rename blast radius in the first pass.

## File-Level Implementation Plan

### `NFTService.swift`

1. Reduce the file to the shell-facing coordinator and small shared support types.
2. Keep:
   - `refreshPhase`
   - in-flight refresh cancellation state
   - provider failure presentation
   - event-recorder wiring
   - refresh freshness surface
3. Remove:
   - metadata preparation helpers
   - persistence snapshot creation
   - SwiftData persistence actor implementation
   - stale cleanup internals
4. Change `fetchAllNFTs(...)` into a sequencing method that delegates each stage to injected collaborators.

### New file: `FetchNFTInventoryUseCase.swift`

1. Introduce a protocol or concrete use case around `any NFTFetching`.
2. Move the “did complete full refresh” decision here.
3. Return a focused output model instead of forcing the coordinator to inspect fetcher internals.

### New file: `PrepareNFTMetadataUseCase.swift`

1. Move:
   - `prepareFetchedNFTs(...)`
   - `prepareMetadataPatches(...)`
   - `deduplicateFetchedNFTs(...)`
2. Keep scope application and metadata patching together so refresh-ready inventory is prepared in one place.
3. Preserve cooperative yielding if large collections still need it.

### New file: `PersistNFTInventoryUseCase.swift`

1. Move persistence snapshot creation and persistence actor code out of `NFTService.swift`.
2. Keep `NFTRefreshPersistenceStore` under this file as a private implementation detail unless another feature needs it.
3. Preserve the existing `@ModelActor` boundary.
4. Keep cleanup conditional on full-refresh completion.

### New file: `NFTRefreshStateComputer.swift`

1. Move refresh-scope normalization and success timestamp bookkeeping into a focused type.
2. Expose:
   - `lastSuccessfulRefreshAt(...)`
   - `markRefreshSucceeded(...)`
   - `reset(...)`
   - optional `isFresh(...)` / `isStale(...)`
3. Keep refresh TTL logic out of persistence and fetch types.

## Safe Migration Order

### Phase 1: Introduce new collaborators without changing behavior

- add the new use-case types and refresh-state type
- keep `NFTService` public API unchanged
- move code with minimal logic changes

Exit criteria:

- app compiles
- behavior is unchanged
- `NFTService` still satisfies existing callers

### Phase 2: Move fetch-completion knowledge behind the fetch use case

- stop reading pagination completion state directly inside the coordinator
- return an explicit fetch result from the fetch use case

Exit criteria:

- coordinator no longer inspects `currentCursor`, `itemsLoaded`, or `total` to decide cleanup behavior

### Phase 3: Move metadata preparation and persistence out of the coordinator

- delegate transformation to `PrepareNFTMetadataUseCase`
- delegate persistence and stale cleanup to `PersistNFTInventoryUseCase`
- leave event recording and phase transitions in the coordinator

Exit criteria:

- `NFTService.swift` no longer contains metadata-patch logic or SwiftData upsert logic

### Phase 4: Stabilize naming and test seams

- decide whether to keep the public name `NFTService` or rename to `NFTRefreshCoordinator`
- add focused tests at each use-case boundary

Exit criteria:

- the coordinator is thin enough that rename becomes optional rather than necessary for clarity

## Testing Strategy

### Unit tests

- `FetchNFTInventoryUseCaseTests`
  - returns raw fetched inventory
  - reports full-refresh completion correctly
  - propagates provider failures
- `PrepareNFTMetadataUseCaseTests`
  - applies account and chain scope
  - decodes base64 token URI metadata when present
  - falls back to raw metadata when token URI decode is unavailable
  - deduplicates repeated NFT ids
- `PersistNFTInventoryUseCaseTests`
  - upserts new NFTs
  - merges existing NFTs without clobbering local-only state such as tags
  - deletes or archives stale NFTs correctly
  - synchronizes tracked NFT counts
  - prunes orphaned contracts and collections
- `NFTRefreshStateComputerTests`
  - tracks last-success timestamps per account/chain scope
  - computes freshness correctly across TTL boundaries
  - resets state cleanly
- `NFTServiceTests`
  - sequences phases in order
  - cancels prior in-flight refreshes when scope changes
  - reuses in-flight work for the same scope
  - records refresh events for success and persistence failure paths

### Regression checks

- refresh a wallet with paginated inventory
- refresh a wallet with duplicate provider entries
- refresh a wallet with inline token URI metadata
- refresh a wallet that removed NFTs since the prior full sync
- verify stale cleanup does not remove playlist-retained NFTs
- verify provider failure presentation still reflects blocking vs degraded states

## Risks To Watch

- extracting use cases but leaving `NFT` mutation logic smeared across coordinator and use-case boundaries
- letting the fetch use case expose fetcher internals instead of a clean result contract
- moving persistence code without preserving the current `@ModelActor` write boundary
- accidentally changing cleanup semantics for partial vs full refreshes
- over-protocolizing purely local implementation details and turning a focused refactor into DI theater

## Decisions Locked By This Plan

These should be treated as settled unless implementation reveals a concrete blocker.

- `NFTService` should become an orchestration boundary, not a second home for transformation and persistence details.
- fetch, metadata preparation, persistence, and refresh-state computation should each have an explicit owner.
- the existing `@ModelActor` persistence boundary should be preserved, not replaced with ad hoc main-actor writes.
- cleanup of stale NFTs must remain conditional on completed full refreshes.
- local-only NFT state such as tags must continue to survive provider refresh merges.
- the shell-facing public name should stay `NFTService` for the first implementation PR. Extract the collaborators first and avoid broad rename churn until the new orchestration shape is proven.
- persistence snapshot creation should live inside `PersistNFTInventoryUseCase`, not `PrepareNFTMetadataUseCase`. The intended seam is `fetch provider inventory -> prepare canonical domain inventory -> persist with persistence-owned translation`.
- `PrepareNFTMetadataUseCase` should own domain preparation only: normalize provider inventory, enrich metadata, and produce canonical NFT content.
- `PersistNFTInventoryUseCase` should own persistence translation and storage correctness: snapshot creation, merge planning, local-state preservation, stale cleanup inputs, conflict handling, write ordering, and SwiftData-specific invariants.




## Recommended First PR

Keep the first PR tight:

1. add `FetchNFTInventoryUseCase`, `PrepareNFTMetadataUseCase`, `PersistNFTInventoryUseCase`, and `NFTRefreshStateComputer`
2. refactor `NFTService` to delegate to them without renaming the public type
3. add unit tests for the extracted metadata and refresh-state types

That gets the biggest architecture win quickly while avoiding a broad shell rename and keeping review scope defensible.
