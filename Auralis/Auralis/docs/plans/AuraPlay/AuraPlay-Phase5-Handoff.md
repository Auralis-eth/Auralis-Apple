# AuraPlay Phase 5 Handoff — NFT Discovery & Metadata Ingestion

This file hands the next engineer from the completed Phase 3 storage-resolution seam into the authoritative Phase 5 work: NFT discovery and metadata ingestion for AuraPlay.

Phase 5 is the full ticket set P5-001 through P5-008. It is not just the earlier Library migration slice. The current app flow already starts when the user enters a wallet address in the gateway view; after they tap the button, the app pulls NFTs. Phase 5 owns making that pull feed the AuraPlay discovery pipeline deliberately, with DTO contracts, provider clients, metadata fetch/parsing, media classification, persistence, artwork prefetch, and integration tests.

## Current Baseline

Phase 3 is complete enough to close.

Everything in `phase3-tickets.md` has been addressed in the codebase:

- `AuraPlayStorageResolutionConfiguration` exists in `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`.
- `URIScheme` classifies IPFS, Arweave, HTTP, HTTPS, `data:`, and unknown URI inputs.
- `URLResolver` synchronously resolves supported storage strings without network access or SwiftData, with the documented bounded `data:` temp-file exception.
- `GatewayFallbackChain` exists above the resolver for HEAD-probed primary/fallback gateway selection.
- `AuraPlayError.mediaResolution(String)` carries storage-resolution failures through the module error surface.
- `AuraPlayDependencies.urlResolver` and `MusicAssembly` live wiring are in place.
- Focused storage-resolution tests and the app-level ship test exist.

The important caveat: Phase 3 built the resolver seam, but downstream discovery, metadata, artwork, and playback callers have not all moved onto it. Phase 5 consumes that seam from the real NFT ingestion path.

## What Is Already Done

The repo already contains useful foundation that Phase 5 should reuse rather than duplicate blindly:

- `ProviderKit` has `AlchemyNFTService` and `AlchemyNFTResponse` for EVM NFT fetching.
- `NFTKit` has fetch/use-case vocabulary, retry/backoff behavior, pagination, typed provider failure mapping, and persistence-oriented refresh concepts. Keep any reusable `NFTFetcher` provider-generic; it must not become an Alchemy-shaped service.
- The gateway flow already triggers NFT pulling after an address is submitted.
- The old `AuralisPrimaryPersistence.NFT` model is still present on current shell and music paths, but it is compatibility state, not the Phase 5 ingestion contract.
- `AuraPlayMediaItem` and `AuraPlayMediaItemService` exist as AuraPlay-owned persisted media projection rows.
- `LiveAuraPlayLibrarySyncService` can mirror already-persisted, already-playable NFTs into the AuraPlay media store.
- The Phase 3 `URLResolver` / `GatewayFallbackChain` stack is implemented and tested.

Treat this as partial infrastructure, not Phase 5 completion. Some current paths still project from existing `NFT` rows with usable audio fields; Phase 5 starts at provider discovery and should move new work through explicit DTO/service contracts instead of re-centering that old model.

## Phase 5 Objective

Build the pipeline:

`Gateway wallet address -> Alchemy/Helius API -> MetadataFetcher for missing metadata -> MetadataParser -> MediaClassifier -> NFT token persistence + AuraPlay media persistence -> ArtworkPrefetcher -> integration tests`

The phase closes only when the P5-008 integration gate passes with zero real API calls.

## Ticket Status Snapshot

| Ticket | Status | Notes |
|---|---:|---|
| P5-000 DTO/contracts | Done initial slice | `NFTTokenDTO`, `MetadataParsed`, `MetadataSchema`, `MediaItemDTO`, provider/fetch/parser/classifier/persistence protocols, and media upsert adapter exist in `MusicFeature/Discovery`. |
| P5-001 Alchemy NFT API v3 client | Partial | Existing Alchemy provider code can be adapted below `EVMNFTDiscovering`, but no Alchemy adapter/client currently returns the Phase 5 DTO contract. Do not make a generic `NFTFetcher` depend on Alchemy details. |
| P5-002 Helius DAS client | Done initial slice | `HeliusNFTClient` implements `SolanaNFTDiscovering` with JSON-RPC request construction, pagination, retry on 429/5xx, owner-mismatch skipping, deduplication, and DTO mapping. |
| P5-003 MetadataFetcher | Done initial slice | `MetadataFetcher` resolves through `GatewayFallbackChain`, decodes JSON `data:` URIs without network, uses `URLCache`, guards 5 MB payloads, retries, and negative-caches failures. |
| P5-004 Metadata schema parsers | Done initial slice | `MetadataParser` returns `MetadataParsed` for Sound.xyz, Zora, Metaplex, ERC-1155, OpenSea, and unknown JSON in the required priority order. |
| P5-005 Media classifier | Done initial slice | `MediaClassifier` turns `MetadataParsed + NFTTokenDTO` into `MediaItemDTO`, resolves URLs through `URLResolver`, disambiguates audio/video, injects dates, and maps to `AuraPlayMediaItemUpsertRequest`. |
| P5-006 NFT sync coordinator | Partial adjacent work | Existing AuraPlay sync mirrors stored NFTs into AuraPlay media. It does not orchestrate provider discovery, missing metadata fetch, classification, debounce, inactive marking, or indexing. |
| P5-007 Artwork prefetch | Not started | No `ArtworkPrefetcher`, URLCache launch config, batch downloader, low-power skip, or 10 MB guard. |
| P5-008 Integration tests | Not started | No `AuraPlayIntegrationTests` target/suite for the 9 discovery scenarios. |

## Start With DTOs And Contracts

Start here before implementing clients. The current code has several useful models, but the Phase 5 pipeline crosses actors and package boundaries. SwiftData `@Model` objects should not become the currency passed through network clients, parsers, classifiers, and model actors.

The DTO layer is the kitchen order ticket: every station can read it, no station owns the whole restaurant, and nobody passes a hot pan through the dining room.

### Why This Comes First

- It fixes the vocabulary before provider-specific code hardens around the wrong shapes.
- It keeps Alchemy, Helius, metadata fetching, parsing, classification, and persistence testable in isolation.
- It prevents `@Model` instances from leaking across actor boundaries.
- It lets existing code adapt gradually: vendor adapters can satisfy the new contracts while any reusable `NFTFetcher` remains provider-generic.
- It makes P5-008 integration tests possible without real network calls.

### Proposed Contract Set

Define these as plain `Sendable` values in the package/module that owns the AuraPlay ingestion boundary. Prefer the smallest package that can depend on `AuralisPrimaryModels.Chain` and be imported by both app composition and tests without pulling SwiftUI.

1. `NFTTokenDTO`

Purpose: provider-normalized ownership record. This is the output of Alchemy/Helius discovery and the input to token persistence, metadata fetching, and classification.

Recommended fields:

- `compositeID: String`
- `chain: Chain` or `chainRawValue: String` if the DTO must stay package-light
- `walletAddress: String`
- `contractAddress: String?`
- `tokenId: String`
- `tokenStandard: String?`
- `collectionName: String?`
- `name: String?`
- `description: String?`
- `imageURL: String?`
- `metadataURL: String?`
- `metadataRaw: String?`
- `providerUpdatedAt: String?`
- `isActive: Bool`
- optional provider diagnostics such as `provider: NFTDiscoveryProvider` if useful for tests/logs

Do not include SwiftData models, URLSession responses, or provider-specific response structs in this DTO. Raw provider payloads can be preserved as strings only when needed for debugging or re-parse.

2. `MetadataParsed`

Purpose: normalized metadata extracted from token JSON. This is parser output and classifier input.

Recommended fields:

- `name: String?`
- `description: String?`
- `creatorName: String?`
- `collectionName: String?`
- `artworkURL: String?`
- `audioURL: String?`
- `videoURL: String?`
- `duration: Double?`
- `format: String?`
- `attributes: [String: String]`
- `schemaVersion: MetadataSchema`
- `rawJSON: String`

Parser output should preserve raw URI strings. Do not call `URLResolver` in the parser.

3. `MetadataSchema`

Purpose: records which schema won detection.

Cases:

- `soundXyz`
- `zora`
- `metaplex`
- `erc1155`
- `openSea`
- `unknown`

Detection order must stay `soundXyz -> zora -> metaplex -> erc1155 -> openSea`. Sound.xyz and Zora are OpenSea-like supersets, so checking OpenSea first creates quiet misclassification.

4. `MediaItemDTO` or `AuraPlayMediaItemDTO`

Purpose: classifier output and persistence input for AuraPlay media rows.

Recommended fields:

- `id: String`
- `nftTokenId: String`
- `title: String`
- `creatorName: String?`
- `collectionName: String?`
- `artworkURL: String?`
- `audioURL: String?`
- `videoURL: String?`
- `durationSeconds: Double?`
- `format: String?`
- `hasAudio: Bool`
- `hasVideo: Bool`
- `isPlayable: Bool`
- `chain: Chain`
- `contractAddress: String?`
- `tokenId: String`
- `walletAddress: String`
- `classifiedAt: Date`
- `createdAt: Date`

Make dates injectable in the classifier, because P5-005 explicitly requires deterministic tests.

5. Provider and service protocols

Define contracts around behavior, not concrete vendors:

- `EVMNFTDiscovering.fetchAll(owner:chain:) async throws -> [NFTTokenDTO]`
- `SolanaNFTDiscovering.fetchAll(owner:) async throws -> [NFTTokenDTO]`
- `TokenMetadataFetching.fetch(metadataURL:) async throws -> String`
- `MetadataParsing.parse(json:) -> MetadataParsed`
- `MediaClassifying.classify(parsed:token:) -> MediaItemDTO`
- `NFTTokenPersisting.upsertAll(_:)`, `activeIDs(...)`, `markInactive(...)`
- `AuraPlayMediaPersisting.upsertAll(_:)` or adapt existing `AuraPlayMediaItemService.replaceAll(...)` behind this protocol
- `ArtworkPrefetching.prefetch(artworkURLs:) async`

These protocols let the coordinator test the full pipeline with fakes and zero real API calls.

### Mapping To Existing Code

- `AlchemyNFTService` can satisfy the provider side through an adapter that maps Alchemy payloads or snapshots into `NFTTokenDTO` without leaking vendor response types past `EVMNFTDiscovering`.
- `NFTFetcher`, if reused, should sit above provider adapters or depend only on provider protocols. It should own generic discovery orchestration concerns such as pagination/retry policy, not Alchemy request/response shapes.
- `AuraPlayMediaItemService.replaceAll(...)` can be adapted, but it currently uses `AuraPlayMediaItemUpsertRequest`, not `MediaItemDTO`; keep the conversion in one adapter rather than spreading field mapping through the coordinator.
- Existing `LiveAuraPlayLibrarySyncService` is a downstream projection from persisted NFTs to AuraPlay media. It is not the full P5-006 coordinator.
- `URLResolver` belongs in the classifier for deterministic URI normalization. `GatewayFallbackChain` belongs in metadata fetching and later runtime paths that need reachability probing.

### Contract Tests To Write First

Before wiring live clients, add small Swift Testing coverage for:

- `NFTTokenDTO.compositeID` normalization for EVM and Solana.
- `MetadataParser` schema priority, especially Sound.xyz before OpenSea.
- `MediaClassifier` audio/video disambiguation with fixed dates.
- `AuraPlayMediaItemService` adapter mapping from `MediaItemDTO` to persisted row fields.
- Coordinator fakes proving no real clients are constructed during tests.

These tests are cheap and prevent the expensive integration scenarios from becoming the first place contract drift shows up.

## Phase 5 Ticket Plan

1. P5-000 Contracts and adapters
   Add the DTOs/protocols above and adapters to existing EVM/persistence code. This is not a user-facing ticket, but it is the safest first implementation slice.

2. P5-001 Alchemy discovery
   Implement or adapt an Alchemy provider adapter/client that returns `NFTTokenDTO` for Ethereum, Polygon, Base, Optimism, and Arbitrum through `EVMNFTDiscovering`. Keep any generic `NFTFetcher` above that adapter and free of Alchemy-specific DTOs, URLs, API-key placement, or response pagination shapes. Keep API keys in the existing provider configuration path unless a broader `AppConfig` lands first.

3. P5-002 Helius discovery
   Add a fresh Helius DAS JSON-RPC client. This is new provider work and also requires `HELIUS_API_KEY` config plumbing.

4. P5-003 MetadataFetcher
   Build the actor over `GatewayFallbackChain`, `URLSession`, `URLCache`, and negative cache. Handle `data:application/json` before network resolution.

5. P5-004 MetadataParser
   Implement schema detection and field extraction as a pure parser returning `MetadataParsed` and never throwing.

6. P5-005 MediaClassifier
   Convert `MetadataParsed + NFTTokenDTO` into `MediaItemDTO`, resolving raw URI strings through `URLResolver` and applying deterministic media-format rules.

7. P5-006 NFTSyncCoordinator
   Compose the provider clients, metadata fetcher, parser, classifier, token persistence, media persistence, debounce, inactive marking, and non-fatal partial errors.

8. P5-007 ArtworkPrefetcher
   Add URLCache-backed prefetching after sync persistence. Keep it fire-and-forget and low-power aware.

9. P5-008 Integration suite
   Build the 9 mock-backed scenarios from the ticket plan. This is the phase gate.

## Phase 5 Non-Goals

Do not treat any of these as implied by Phase 5:

- replacing the shared audio engine
- making AuraPlay own shell routing
- adding a second router under the music feature
- introducing playlist persistence
- adding durable playback state beyond fields needed to persist classified media
- removing legacy music code before migrated UI parity is proven
- expanding search, Spotlight, or semantic embeddings beyond the hooks needed by P5-006 unless those tickets are explicitly pulled in

## Guardrails For The Handoff

- The gateway flow remains the user entry point for address submission and initial NFT pull.
- The shell still owns account state, chain scope, and app routing.
- AuraPlay owns music presentation state and the media projection it needs for playback/library surfaces.
- Keep `ModelContainer` as the shared persistence injection point; do not pass `ModelContext` around globally.
- Do not pass SwiftData `@Model` values across actor boundaries. Use DTOs.
- Leaf SwiftUI views should not talk directly to provider clients, metadata fetchers, or `AudioEngine`.
- Storage resolution stays module-owned in `MusicFeature`; legacy app-target URL helpers remain compatibility references until their callers are deliberately migrated.
- If a URL path needs only deterministic normalization, use `URLResolver`. If it needs gateway liveness, use `GatewayFallbackChain` above the resolver.
- Tests for Phase 5 must use mocks/fakes and make zero real Alchemy, Helius, or metadata HTTP calls.

## Files Worth Opening First

- `Auralis/Auralis/docs/plans/AuraPlay/AuraPlay-Status.md`
- `Auralis/Auralis/docs/plans/AuraPlay/AuraPlay-Gaps.md`
- `Auralis/Auralis/docs/plans/AuraPlay/AuraPlay-LLM-Context.md`
- `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`
- `MusicFeature/Sources/MusicFeature/Persistence/AuraPlayMediaItem.swift`
- `MusicFeature/Sources/MusicFeature/Persistence/Services/AuraPlayMediaItemService.swift`
- `Auralis/Auralis/MusicApp/AuraPlay/Services/AuraPlayLibrarySyncing.swift`
- `ProviderKit/Sources/ProviderKit/Alchemy/AlchemyNFTService.swift`
- `ProviderKit/Sources/ProviderKit/NFT/AlchemyNFTResponse.swift`
- `NFTKit/Sources/NFTProviderAdapters/NFTFetcher.swift`
- `NFTKit/Sources/NFTProviderAdapters/FetchNFTInventoryUseCase.swift`
- `NFTKit/Sources/NFTPresentation/PrepareNFTMetadataUseCase.swift`
- `Auralis/Auralis/Assemblies/MusicAssembly.swift`
- `Auralis/Auralis/Config/Secrets.local.xcconfig.template`

## Phase 5 Definition Of Done

Phase 5 closes when:

- P5-001 through P5-008 are implemented or explicitly superseded by equivalent code with matching acceptance coverage.
- The gateway address-submit flow can drive NFT discovery into the Phase 5 pipeline.
- EVM discovery covers the five supported Alchemy chains.
- Solana discovery uses Helius DAS with mocked test coverage.
- Missing metadata is fetched through the resolver/fallback seam with cache and guardrails.
- The five metadata schemas parse in the required priority order.
- Media classification handles audio/video/non-playable items deterministically.
- Token/media persistence receives DTOs, not SwiftData models from network/parser code.
- Artwork prefetch uses URLCache and does not block sync completion.
- P5-008's 9 integration scenarios pass with zero real API calls.
- A clean Xcode build passes.

## Known Risks Going Into Phase 5

- mistaking the existing Library projection path for the full discovery pipeline
- duplicating the current Alchemy stack instead of adapting it cleanly
- letting provider response structs leak into parser/classifier/persistence contracts
- crossing actor boundaries with SwiftData `@Model` instances
- checking OpenSea before Sound.xyz or Zora and silently losing music metadata
- resolving URLs in both parser and classifier, creating inconsistent normalization
- treating Helius/Solana as a small variation of the EVM path when its pagination and ownership shape are different
- allowing tests to touch real network clients because composition lacks clear protocols

## Next Engineer Checklist

1. Add the Phase 5 DTOs/protocols and their focused tests.
2. Write adapters from existing EVM fetch/persistence code into the DTO contracts.
3. Implement Helius discovery behind the same discovery boundary.
4. Add MetadataFetcher, MetadataParser, and MediaClassifier as isolated units.
5. Compose `NFTSyncCoordinator` only after the units are tested.
6. Add `ArtworkPrefetcher` and URLCache launch configuration.
7. Build the P5-008 integration scenarios with fakes and an in-memory container.
8. Build the project.
9. Update `AuraPlay-Status.md`, `AuraPlay-Gaps.md`, and `Journal.md` as tickets close.
