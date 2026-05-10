# SPM ChainProviders Implementation Strategy

## Purpose

`ChainProviders` should define chain-level capabilities and provider selection. It should answer questions like: which chains support EVM RPC, which chains support ERC-20 holdings, which provider should handle a read on this chain, and how should chain-specific network capabilities be exposed to the rest of the app?

This package should not be a second copy of `ProviderKit`. `ProviderKit` owns transport and vendor clients. `ChainProviders` owns chain capability policy and provider composition.

## Current Code To Move First

Move or re-home these app-local chain/provider boundary files:

- `Auralis/Auralis/Networking/Chain+ProviderSupport.swift`
- `Auralis/Auralis/DataModels/Chain.swift` extension that maps `Chain` to `web3.EthereumNetwork`, if ENS or Ethereum adapters still need `web3`
- `Auralis/Auralis/Networking/ReadOnlyProviderFactory.swift`, after `ProviderKit` owns the concrete Alchemy clients

Also consider moving provider-facing protocols currently scattered across `NFTKit` if they are not NFT-specific:

- `NativeBalanceProviding`
- `GasPricingProviding`
- generic token-balance capability protocols if they are chain-level rather than NFTKit-specific

Keep NFT inventory-specific protocols in `NFTKit` unless other packages need to fetch NFT inventory without importing `NFTKit`.

## Package Boundary

Recommended product:

```swift
.library(name: "ChainProviders", targets: ["ChainProviders"])
```

Recommended dependencies:

- `AuralisPrimaryModels`
- `ProviderKit`
- `web3.swift` only if the `Chain -> EthereumNetwork` mapping must stay public and shared
- `Foundation`

Avoid dependencies on:

- SwiftUI
- SwiftData
- app shell state
- receipts
- ENS cache implementation
- NFT persistence

`ChainProviders` can depend on `ProviderKit`, but `ProviderKit` should not depend on `ChainProviders`.

## What Belongs Here

- chain capability rules such as `supportsEVMRPC` and `supportsERC20Holdings`
- provider selection/composition for read-only chain operations
- chain-specific adapter values needed by downstream clients
- unsupported-chain handling policy
- factory/builder protocols for read-only providers
- multi-provider fallback policy if Auralis later adds non-Alchemy providers

## What Should Stay Out

- Alchemy URL construction and HTTP calls
- API-key lookup
- NFT metadata persistence
- ENS cache and resolution policy
- explorer URL copy/presentation
- shell current-chain selection
- SwiftUI error banners

## Migration Order

1. Create `ChainProviders` with only chain capability extensions.
2. Move `supportsEVMRPC` and `supportsERC20Holdings` from the app target.
3. Keep `web3.swift` out of this package unless non-ENS code needs it. If only ENS uses `EthereumNetwork`, keep that mapping in the `ENS` package instead of making every chain provider consumer pay for `web3`.
4. Move read-only capability protocols that are chain-level, not NFT-specific.
5. After `ProviderKit` owns Alchemy clients, move `ReadOnlyProviderFactory` into `ChainProviders` as a composition factory.
6. Update app shell/composition to import `ChainProviders` for capability checks and provider creation.
7. Remove app-local chain provider extensions after all call sites compile against the package.

## Suggested Types

- `ChainCapabilitySet`
- `ChainProviderCapabilities`
- `ReadOnlyChainProviderFactory`
- `ReadOnlyChainProviderBuilding`
- `ChainProviderUnsupportedCapability`
- `EVMChainAdapter` if `web3` mapping is shared

The naming should keep a clear line between capability policy and concrete transport. For example, `ReadOnlyChainProviderFactory` can build an `AlchemyGasPricingProvider`, but the Alchemy provider implementation itself belongs in `ProviderKit`.

## Dependency Direction Rule

`AuralisPrimaryModels` owns `Chain` as a domain model. `ChainProviders` extends it with provider-facing capabilities. Feature packages ask `ChainProviders` what is possible and ask `ProviderKit` clients to perform the work.

That avoids stuffing provider rules into the model package while still removing these decisions from UI files.

## Testing Strategy

Add Swift Testing coverage for:

- every `Chain` case and its EVM RPC support
- every `Chain` case and ERC-20 holdings support
- unsupported-chain errors for native balance, gas, and token holdings construction
- provider factory output when a shared session/config resolver is injected
- future fallback order if multiple vendors are added

Tests should fail loudly when a new chain case is added without an explicit capability decision.

## Success Criteria

- UI code no longer asks raw chain/provider questions through app-local extensions.
- Provider factories live outside SwiftUI and shell views.
- New chain support requires a small, explicit capability update.
- `ProviderKit` remains transport-focused while `ChainProviders` remains policy/composition-focused.
