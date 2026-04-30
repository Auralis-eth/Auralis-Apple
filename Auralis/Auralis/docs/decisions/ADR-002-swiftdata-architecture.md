# ADR-002: AuraPlay SwiftData Architecture

## Status

Accepted

## Context

AuraPlay Phase 2 introduces durable music data, but the module already has a clear shell boundary from Phase 1:

- the shell owns account and chain selection
- `AuraPlayTabRootView` owns live dependency construction
- `AuraPlayCompositionRoot` owns module composition
- views already depend on explicit AuraPlay seams instead of global state

The persistence layer needs to fit that shape instead of starting a parallel architecture.

## Decision

AuraPlay uses one shared SwiftData `ModelContainer`, versioned schemas, and service-local contexts.

The concrete rules are:

1. `AppModelContainer.make(inMemory:)` is the only AuraPlay container factory.
2. `ModelContainer` is the only persistence object shared through dependency injection.
3. Non-view persistence work uses `@ModelActor` services, each with its own private `ModelContext` derived from that shared container.
4. SwiftUI views may use `@Query` when Phase 2 surfaces become query-backed, but views do not orchestrate persistence writes directly.
5. SwiftData errors stay behind AuraPlay-owned error mapping before they reach UI-facing surfaces.

## Why This Shape

### One shared `ModelContainer`, private `ModelContext` per service

The container is the storage contract. It owns schema, migration plan, and store configuration.

`ModelContext` is operational state. Sharing a single mutable context across unrelated services would blur ownership, make write behavior harder to reason about, and create exactly the kind of “who changed this graph?” debugging story that Phase 2 should avoid.

The result is simple:

- dependency injection shares the stable container
- each service owns its own working context
- service boundaries stay explicit

### `@Query` in views, `@ModelActor` in non-view code

Views are good at reflecting persisted state. They are bad places to hide mutation workflows, indexing side effects, or wallet-scoped upsert logic.

`@Query` stays appropriate for read-driven SwiftUI presentation once AuraPlay surfaces graduate from the Phase 1 summary. `@ModelActor` stays appropriate for background mutation and query services because it keeps SwiftData work isolated and naturally aligned with Swift concurrency.

### No repository-protocol layer for raw persistence access

AuraPlay already has a repository seam where the product needs one: `AuraPlayLibraryRepository`.

Adding another generic repository abstraction beneath SwiftData would mostly duplicate framework concepts while making debugging and migrations worse. Phase 2 wants concrete persistence services with clear responsibilities, not a stack of wrappers that say “repository” three times and still need the same fetch descriptors underneath.

### `MediaItem` uses capability flags instead of inheritance

The library UI needs one query-friendly model that can answer questions like:

- is this playable?
- does it have artwork?
- does it have waveform-ready audio?
- can it participate in search and playlists?

Boolean capability flags keep those answers close to the model without forcing an inheritance tree for every “track versus clip versus collectible with audio” variation. That is a better fit for SwiftData predicates and for the likely evolution of NFT-derived media metadata.

### Search stays three-tier and Apple-native

AuraPlay search has three distinct jobs:

- instant prefix matching while the person types
- richer fuzzy and system-facing retrieval
- intent-style matching over natural-language queries

The chosen tools map directly to those jobs:

- trie for prefix matches
- CoreSpotlight for indexed retrieval and system surfacing
- NaturalLanguage embeddings for semantic intent

This avoids introducing a second database stack, keeps the implementation aligned with Apple frameworks already available in the app environment, and preserves a clean search boundary behind one `SearchService`.

## Consequences

- AuraPlay gets a persistence spine that matches the Phase 1 architecture instead of bypassing it.
- Future entity services can share one migration-aware container without sharing one mutable context.
- The module remains testable with in-memory containers.
- Search, playlists, and playback history can be added incrementally without turning views into persistence coordinators.
