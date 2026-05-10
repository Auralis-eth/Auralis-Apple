# SPM ENS Implementation Strategy

## Decision

Create a first-class `ENS` SPM package and move the ENS domain currently living in `AgentIdentityCore` into it. ENS is the long-term home for core ENS types. Do not keep ENS as a permanent sub-area of `AgentIdentityCore`, and do not make an `ENSAdapter` package the home for core ENS types.

The clean boundary is:

- `ENS`: ENS domain contracts, cache records, resolution errors/provenance, live Web3 ENS client, resolver builders, and provider-configuration adapter.
- `AgentIdentityCore`: agent/account identity concepts only. During migration it may temporarily re-export or typealias ENS types for compatibility, but it should not own ENS long term.
- app target: composition and UI only.

This supersedes the earlier narrow `ENSAdapter` recommendation. A separate adapter target is only worth creating later if provider/receipt wiring becomes large enough to justify a second package.

## Why Not Keep It In AgentIdentityCore?

The listed ENS types are already a complete subdomain:

- `ENSResolving`
- `ENSResolvers`
- `EthereumNameServiceClient`
- `Web3EthereumNameServiceClient`
- `ENSResolutionCacheStore`
- ENS forward/reverse cache entries
- ENS resolution errors and provenance

Keeping that inside `AgentIdentityCore` makes the package name lie. ENS can support agent identity, profile display, account entry, and trust presentation, but it is not itself agent identity.

## Why Not Put Everything In ENSAdapter?

`ENSAdapter` implies glue code around another domain. The listed types are not glue; they are the ENS domain and live implementation. Naming the package `ENS` gives the future dependency graph a truthful center.

## Current Code To Move First

Move from `AgentIdentityCore/Sources/AgentIdentityCore/` into `ENS/Sources/ENS/`:

- `ENSResolving.swift`
- `ENSResolvers.swift`
- `EthereumNameServiceClient.swift`
- `Web3EthereumNameServiceClient.swift`
- `Web3EthereumNameServiceResolver.swift`
- `UnavailableEthereumNameServiceClient.swift`
- `ENSResolutionCacheStore.swift`
- `ENSCacheResetService.swift`
- `ENSCacheState.swift`
- `ENSForwardCacheEntry.swift`
- `ENSForwardResolution.swift`
- `ENSReverseCacheEntry.swift`
- `ENSReverseResolution.swift`
- `ENSResolutionError.swift`
- `ENSResolutionProvenance.swift`
- `ENSProviderConfiguration.swift`
- `ENSEventRecording.swift`
- `NoOpENSEventRecorder.swift`

Move from the app target into `ENS` after `ProviderKit` exists:

- `Auralis/Auralis/Networking/AppENSResolvers.swift`, renamed/split as provider-backed ENS configuration and live factory support
- `Auralis/Auralis/DataModels/Chain.swift` Web3 mapping if ENS is still the only consumer

Keep app-side unless later generalized:

- `Auralis/Auralis/Networking/ReceiptBackedENSEventRecorder.swift`, because receipt event taxonomy may remain product-specific

## Package Boundary

Recommended product:

```swift
.library(name: "ENS", targets: ["ENS"])
```

Recommended dependencies:

- `AuralisPrimaryModels`
- `ProviderKit`
- `web3.swift`
- `Foundation`

Optional later dependencies:

- `ReceiptsCore` only if receipt-backed ENS event recording moves into the package
- storage packages only if ENS cache persistence becomes externalized

Avoid dependencies on:

- SwiftUI
- SwiftData unless the ENS cache becomes persisted here
- app target
- NFTKit
- ExplorerAdapter

## What Belongs Here

- ENS resolver protocols
- live/unavailable ENS clients
- Web3 ENS implementation
- forward/reverse cache records and in-memory cache store
- ENS resolution errors, provenance, and cache reset support
- ENS provider configuration contracts
- adapter from `ProviderKit.ProviderConfigurationResolving` to `ENSProviderConfigurationResolving`
- live resolver factory used by app composition

## What Should Stay Out

- address-entry UI
- profile rendering
- account CRUD
- NFT and token fetching
- generic provider transport
- explorer URL building
- receipt UI
- shell state

## Migration Order

1. Create `ENS/Package.swift` with dependencies on `AuralisPrimaryModels` and `web3.swift`.
2. Move ENS domain/client/cache files from `AgentIdentityCore` into `ENS` without behavioral changes.
3. Add compatibility typealiases or re-exports in `AgentIdentityCore` only if needed to reduce call-site churn.
4. Update app and test imports from `AgentIdentityCore` to `ENS` where they use ENS types directly.
5. After `ProviderKit` exists, move provider-backed ENS configuration from `AppENSResolvers.swift` into `ENS`.
6. Keep receipt-backed ENS recording app-side unless a later ticket moves receipt adapters out of the app.
7. Remove compatibility shims from `AgentIdentityCore` once callers are migrated.

## Testing Strategy

Add Swift Testing coverage in `ENS` for:

- forward and reverse cache hit/miss/expiry behavior
- unavailable client failure mapping
- Web3 client configuration mapping for supported chains
- provider configuration failure mapping after `ProviderKit` integration
- resolver provenance for cache and live results
- cache reset behavior

## Success Criteria

- ENS core types live in an `ENS` package.
- `AgentIdentityCore` no longer owns ENS implementation details after compatibility shims are removed.
- The app target imports `ENS` for ENS behavior and only composes live dependencies.
- Provider configuration translation is tested outside SwiftUI.
