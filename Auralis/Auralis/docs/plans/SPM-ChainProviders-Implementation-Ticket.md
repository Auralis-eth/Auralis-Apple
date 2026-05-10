# Ticket: Extract ChainProviders

## Status

Blocked until `ProviderKit` exists if this ticket moves provider factory construction. The chain capability portion can be implemented before `ProviderKit`.

## Goal

Create `ChainProviders`, the package that owns provider-facing chain capability policy and read-only provider composition. It should answer what each `Chain` supports and build the right provider clients without making UI code know vendor details.

## Source Strategy

Use this with `SPM-ChainProviders-Implementation-Strategy.md`.

## Package To Create

Path:

- `ChainProviders/Package.swift`
- `ChainProviders/Sources/ChainProviders/`
- `ChainProviders/Tests/ChainProvidersTests/`

Manifest:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChainProviders",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ChainProviders", targets: ["ChainProviders"]),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../ProviderKit"),
    ],
    targets: [
        .target(
            name: "ChainProviders",
            dependencies: ["AuralisPrimaryModels", "ProviderKit"]
        ),
        .testTarget(
            name: "ChainProvidersTests",
            dependencies: ["ChainProviders"]
        ),
    ]
)
```

Do not add `web3.swift` here unless more than ENS needs the `Chain -> EthereumNetwork` mapping. Prefer putting that mapping in `ENS`.

## Files To Move

Move from app target:

- `Auralis/Auralis/Networking/Chain+ProviderSupport.swift` -> `ChainProviders/Sources/ChainProviders/Chain+ProviderCapabilities.swift`

Move after `ProviderKit` exists:

- `Auralis/Auralis/Networking/ReadOnlyProviderFactory.swift` -> `ChainProviders/Sources/ChainProviders/ReadOnlyProviderFactory.swift`

Do not move:

- `Auralis/Auralis/DataModels/Chain.swift` Web3 extension unless it is not moved into `ENS`
- UI state for selected chain/current account
- Alchemy provider implementations

## Public API Requirements

Expose:

```swift
public extension Chain {
    var supportsEVMRPC: Bool { ... }
    var supportsERC20Holdings: Bool { ... }
}
```

Expose provider factory only after `ProviderKit` is in place:

```swift
public struct ReadOnlyProviderFactory: Sendable {
    public init(configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(), session: URLSession? = nil)
    public func makeGasPricingProvider() -> any GasPricingProviding
    public func makeNativeBalanceProvider() -> any NativeBalanceProviding
    public func makeTokenHoldingsProvider() -> any TokenHoldingsProviding
    public func makeTokenBalancesProvider() -> any TokenBalancesProviding
    public func makeNFTInventoryProvider(for chain: Chain) throws -> any NFTInventoryProviding
}
```

If `NFTInventoryProviding` and token protocols still live in `NFTKit`, either keep those factory methods app-side for now or add a `NFTKit` dependency deliberately. Do not create a circular dependency.

## Implementation Steps

1. Create `ChainProviders` with only `Chain+ProviderCapabilities.swift`.
2. Update app and package call sites to import `ChainProviders` where `supportsEVMRPC` or `supportsERC20Holdings` is used.
3. Add tests covering every `Chain` case.
4. After `ProviderKit` exists, move `ReadOnlyProviderFactory` if its return protocols are available without a cycle.
5. If moving factory requires importing `NFTKit`, stop and split the factory: generic gas/native balance factory in `ChainProviders`, NFT/token inventory factory remains in `NFTKit` or app composition until protocol ownership is clarified.
6. Add the package product to the app target.
7. Build.

## Non-Goals

- Do not add multi-provider fallback.
- Do not change chain support decisions.
- Do not move UI chain selection state.
- Do not force `web3.swift` into this package for ENS only.

## Test Requirements

Add Swift Testing tests for:

- `supportsEVMRPC == false` for `solanaMainnet` and `solanaDevnetTestnet`
- `supportsEVMRPC == true` for every current EVM chain
- `supportsERC20Holdings == false` for Solana chains
- `supportsERC20Holdings == true` for every current EVM chain
- factory injects the provided configuration resolver and session, if factory is moved

Use exhaustive `Chain.allCases` or equivalent. If `Chain` is not `CaseIterable`, add a local test list and include a comment requiring new chain cases to update tests.

## Acceptance Criteria

- Capability checks live in `ChainProviders`, not app-local networking files.
- App build succeeds with `import ChainProviders` at call sites.
- Tests fail if a new chain case lacks an explicit capability decision.
- `ReadOnlyProviderFactory` is moved only if it does not create a cycle.

## Rollback Plan

If factory extraction creates a dependency cycle, keep `ReadOnlyProviderFactory` app-side and complete only the capability extraction. Record the factory as a follow-up in this ticket instead of weakening the dependency graph.
