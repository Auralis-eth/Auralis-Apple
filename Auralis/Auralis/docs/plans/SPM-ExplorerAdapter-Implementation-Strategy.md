# SPM ExplorerAdapter Implementation Strategy

## Purpose

`ExplorerAdapter` should own blockchain-explorer destination building and validation. Today Auralis has outbound OpenSea/external-link infrastructure, but no dedicated explorer package. This package should provide typed URLs for addresses, transactions, tokens, NFTs, and collections across supported chains while keeping UI confirmation and browser-opening behavior in `OperatorCore` and the app.

This package is a URL policy and destination package. It is not a networking provider and should not fetch explorer pages.

## Current Code To Move Or Build Around

There is no obvious existing `ExplorerAdapter` implementation in the current project structure. The first implementation should build new types and then replace scattered URL construction call sites as they appear.

Potential app-side call sites to review during implementation:

- `Auralis/Auralis/Aura/Newsfeed/Components/OpenSeaLink.swift`
- `Auralis/Auralis/Aura/Newsfeed/Components/ExternalLinkConfirmationSheet.swift`
- NFT detail views that build marketplace or explorer URLs
- token detail views that need address/token explorer links
- receipt views that may eventually link to transaction or account context

Do not move the confirmation sheet into this package. That belongs in SwiftUI/app or `OperatorCore`.

## Package Boundary

Recommended product:

```swift
.library(name: "ExplorerAdapter", targets: ["ExplorerAdapter"])
```

Recommended dependencies:

- `AuralisPrimaryModels`
- `OperatorCore` only if it should emit `ExternalLinkCandidate`/destination values directly
- `Foundation`

Avoid dependencies on:

- SwiftUI
- SwiftData
- provider network packages
- NFTKit unless NFT-specific explorer builders require package-only types
- receipts unless event logging is explicitly added later

If possible, keep `ExplorerAdapter` independent of `OperatorCore` and let the app convert typed explorer destinations into operator open requests. That keeps this package usable in tests and non-UI contexts.

## What Belongs Here

- explorer host/base URL catalog by chain
- typed destination models:
  - account/address
  - transaction hash
  - token contract
  - NFT contract/token ID
  - collection/marketplace slug when supported
- URL builders with validation
- chain support/fallback rules for explorer links
- marketplace-specific link builders such as OpenSea if treated as explorer-like outbound destinations
- allowlist metadata that `OperatorCore` can consume

## What Should Stay Out

- opening URLs
- confirmation modals
- SwiftUI buttons
- receipt writing for link opens
- network calls to explorer APIs
- Alchemy or RPC configuration
- ENS resolution
- NFT metadata fetch orchestration

## Migration Order

1. Create `ExplorerAdapter` with typed destination structs and a small explorer catalog.
2. Add builders for the current highest-value destinations: Ethereum address, token contract, transaction, and NFT asset links.
3. Add chain support decisions for Auralis-supported chains. Unsupported chains should fail with a typed error, not return malformed URLs.
4. Update `OpenSeaLink` and any NFT/token detail URL construction to use `ExplorerAdapter` builders.
5. Route generated URLs through existing `OperatorCore`/app confirmation flow.
6. Add allowlist handoff metadata if `OperatorCore` needs to validate explorer hosts centrally.
7. Expand only when a feature needs a new destination type.

## Suggested Types

- `ExplorerDestination`
- `ExplorerDestinationBuilder`
- `ExplorerCatalog`
- `ExplorerHostPolicy`
- `ExplorerURLBuildError`
- `MarketplaceDestinationBuilder`
- `OpenSeaDestinationBuilder`

Example shape:

```swift
public enum ExplorerDestination: Equatable, Sendable {
    case address(String, chain: Chain)
    case transaction(String, chain: Chain)
    case token(contract: String, chain: Chain)
    case nft(contract: String, tokenID: String, chain: Chain)
}

public protocol ExplorerURLBuilding: Sendable {
    func url(for destination: ExplorerDestination) throws -> URL
}
```

## Address And Token Safety Rules

- Normalize Ethereum addresses before building links.
- Reject empty transaction hashes and token IDs.
- Reject unknown or unsupported chains explicitly.
- Keep marketplace slugs separate from contract/token-ID explorer destinations.
- Avoid silently falling back from chain-specific explorers to Ethereum mainnet URLs.

Silent fallback is dangerous here because a wrong explorer URL can make users trust the wrong asset or account.

## Testing Strategy

Add Swift Testing coverage for:

- URL output for every supported chain/destination pair
- unsupported-chain failures
- malformed address/hash/token-ID failures
- OpenSea URL generation for NFT assets if included
- host allowlist output for `OperatorCore`
- no accidental mainnet fallback for non-mainnet chains

A small table-driven test suite should be enough. Explorer link behavior is deterministic and should not require network access.

## Success Criteria

- Explorer and marketplace URLs are built by typed package code, not string interpolation in views.
- UI components receive a URL or typed failure; they do not know explorer host rules.
- Outbound link confirmation remains centralized through existing operator/app UI.
- New explorer destinations can be added without editing unrelated feature views.
