# ADR-012: NFT Refresh Is A Focused Use-Case Pipeline

## Status

Accepted and implemented.

## Context

The original `NFTService` combined provider pagination, metadata preparation, persistence, stale-record cleanup, freshness computation, and presentation state. That made provider and storage changes difficult to test independently.

## Decision

- `NFTService` remains a thin presentation-facing refresh coordinator.
- Inventory fetching, metadata preparation, persistence, refresh-state computation, and receipt/event recording are separate collaborators owned by `NFTKit`.
- Provider adapters return typed failures rather than leaking transport errors to presentation.
- Stale cleanup runs only after a complete refresh; partial or failed inventory fetches must not delete previously persisted NFTs.
- SwiftData mutation remains behind persistence-owned actors and use cases.

## Evidence

- `NFTKit` contains focused inventory-fetch, metadata-preparation, persistence, refresh-state, and presentation targets.
- Dedicated tests cover `FetchNFTInventoryUseCase`, `PrepareNFTMetadataUseCase`, `PersistNFTInventoryUseCase`, `NFTRefreshStateComputer`, and the coordinating `NFTService`.
- App assemblies inject the concrete provider, persistence, and receipt collaborators.

## Consequences

- Network, transformation, persistence, and UI state can evolve and be tested independently.
- Pagination completion and destructive cleanup rules are explicit pipeline contracts.
- The app target composes NFT behavior but does not own the reusable pipeline.
