# Ticket: Extract ProviderKit

## Status

Ready for implementation after current workspace changes are clean enough to safely move package files.

## Goal

Create a local Swift package named `ProviderKit` that owns provider configuration, API-key/secret lookup, HTTP/RPC transport helpers, retry behavior, shared provider error vocabulary, and live Alchemy clients. After this ticket, app/UI code should not construct Alchemy URLs or own API-key-backed network calls.

## Source Strategy

Use this with `SPM-ProviderKit-Implementation-Strategy.md`.

## Package To Create

Path:

- `ProviderKit/Package.swift`
- `ProviderKit/Sources/ProviderKit/`
- `ProviderKit/Tests/ProviderKitTests/`

Manifest:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProviderKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ProviderKit", targets: ["ProviderKit"]),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
    ],
    targets: [
        .target(
            name: "ProviderKit",
            dependencies: ["AuralisPrimaryModels"]
        ),
        .testTarget(
            name: "ProviderKitTests",
            dependencies: ["ProviderKit"]
        ),
    ]
)
```

## Files To Move

Move from `NFTKit/Sources/NFTKit/Support/`:

- `ProviderEndpointConfiguration.swift` -> `ProviderKit/Sources/ProviderKit/Configuration/ProviderEndpointConfiguration.swift`
- `ProviderConfigurationResolving.swift` -> `ProviderKit/Sources/ProviderKit/Configuration/ProviderConfigurationResolving.swift`
- `LiveProviderConfigurationResolver.swift` -> `ProviderKit/Sources/ProviderKit/Configuration/LiveProviderConfigurationResolver.swift`
- `Secrets.swift` -> `ProviderKit/Sources/ProviderKit/Configuration/Secrets.swift`
- `RetryAfterSupport.swift` -> `ProviderKit/Sources/ProviderKit/Transport/RetryAfterSupport.swift`
- `RequestThrottler.swift` -> `ProviderKit/Sources/ProviderKit/Transport/RequestThrottler.swift`
- `String+EthereumAddress.swift` -> `ProviderKit/Sources/ProviderKit/Support/String+EthereumAddress.swift`
- `DecimalQuantityFormatter.swift` -> `ProviderKit/Sources/ProviderKit/Support/DecimalQuantityFormatter.swift`
- `ProviderAbstractionError.swift` -> `ProviderKit/Sources/ProviderKit/Failures/ProviderAbstractionError.swift`

Move from `NFTKit/Sources/NFTKit/Failures/` if the failures are shared outside NFT inventory:

- `NFTProviderFailure.swift` -> `ProviderKit/Sources/ProviderKit/Failures/NFTProviderFailure.swift`
- `NFTProviderFailureKind.swift` -> `ProviderKit/Sources/ProviderKit/Failures/NFTProviderFailureKind.swift`
- `NFTProviderFailurePresentationMode.swift` -> `ProviderKit/Sources/ProviderKit/Failures/NFTProviderFailurePresentationMode.swift`

Keep presentation copy in `NFTKit` unless the implementation proves it is provider-generic.

Move from app target:

- `Auralis/Auralis/Networking/AlchemyRPCProvider.swift` -> `ProviderKit/Sources/ProviderKit/Alchemy/AlchemyRPCProvider.swift`
- `Auralis/Auralis/Networking/AlchemyGasPricingProvider.swift` -> `ProviderKit/Sources/ProviderKit/Alchemy/AlchemyGasPricingProvider.swift`

Split later, not in the first compiling checkpoint:

- transport pieces of `NFTKit/Sources/NFTKit/Providers/AlchemyNFTService.swift`
- transport pieces of `NFTKit/Sources/NFTKit/Providers/AlchemyTokenHoldingsProvider.swift`

## Public API Requirements

Ensure these types/protocols remain public if used outside `ProviderKit`:

- `ProviderEndpointConfiguration`
- `ProviderConfigurationResolving`
- `LiveProviderConfigurationResolver`
- `ProviderAbstractionError`
- `RequestThrottler`
- `RetryAfterSupport` helpers needed by clients
- `NativeBalanceProviding`
- `GasPricingProviding`
- `AlchemyRPCProvider`
- `AlchemyGasPricingProvider`

If `NativeBalanceProviding` and `GasPricingProviding` currently live elsewhere, move them here only if they are chain/provider capabilities rather than UI contracts.

## Implementation Steps

1. Create `ProviderKit` manifest and source/test folders.
2. Move configuration, secrets, retry, throttling, quantity, address, and provider error files first.
3. Update `NFTKit/Package.swift` to depend on `../ProviderKit`.
4. Replace moved file imports in `NFTKit` with `import ProviderKit`.
5. Move `AlchemyRPCProvider` and `AlchemyGasPricingProvider` into `ProviderKit`.
6. Update app target files that reference those providers to import `ProviderKit`.
7. Update app package/project dependency to include `ProviderKit` product.
8. Keep `ReadOnlyProviderFactory` app-side until `ChainProviders` exists.
9. Run package tests and app build.

## Non-Goals

- Do not redesign Alchemy behavior.
- Do not move SwiftData persistence.
- Do not move ENS provider configuration in this ticket.
- Do not move `ReadOnlyProviderFactory` yet.
- Do not create multi-provider fallback logic yet.

## Test Requirements

Add Swift Testing tests in `ProviderKitTests` for:

- configuration success for a known supported chain
- missing API key maps to `ProviderAbstractionError.missingAPIKey`
- invalid endpoint maps to `ProviderAbstractionError.invalidURL`
- numeric `Retry-After`
- HTTP-date `Retry-After`
- RPC envelope success decode
- RPC envelope error mapping for rate limit, unauthorized, unsupported method, generic provider error
- native balance hex quantity to decimal conversion

Use injected `URLSession`/`URLProtocol` stubs or existing local request stubs. Do not hit live Alchemy.

## Acceptance Criteria

- `ProviderKit` exists as a local package and builds independently.
- `NFTKit` compiles using `ProviderKit` imports for moved provider primitives.
- App build succeeds.
- No SwiftUI file constructs an Alchemy provider directly except composition/factory code.
- Existing provider-facing tests still pass or are moved into `ProviderKitTests`.

## Rollback Plan

If the package move breaks too many call sites, keep `ProviderKit` with configuration/error primitives only, revert the Alchemy provider file moves, and finish the compile by importing `ProviderKit` from `NFTKit`. Do not delete the partial package unless the manifest itself blocks the app build.
