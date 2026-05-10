# SPM ProviderKit Implementation Strategy

## Purpose

`ProviderKit` should become the network-provider foundation for Auralis. Its job is to own provider configuration, API-key routing, HTTP/RPC transport, retry/backoff behavior, rate-limit parsing, provider error mapping, and provider-family clients such as Alchemy.

The app target should ask for capabilities like "fetch NFT inventory", "fetch token balances", "read gas price", or "read native balance". It should not know how to build Alchemy URLs, where API keys live, how RPC envelopes are encoded, or how transport errors become product-facing provider failures.

## Current Code To Move First

Move these existing app or package concerns into `ProviderKit`:

- `NFTKit/Sources/NFTKit/Support/ProviderEndpointConfiguration.swift`
- `NFTKit/Sources/NFTKit/Support/ProviderConfigurationResolving.swift`
- `NFTKit/Sources/NFTKit/Support/LiveProviderConfigurationResolver.swift`
- `NFTKit/Sources/NFTKit/Support/Secrets.swift`
- `NFTKit/Sources/NFTKit/Support/RetryAfterSupport.swift`
- `NFTKit/Sources/NFTKit/Support/RequestThrottler.swift`
- `NFTKit/Sources/NFTKit/Support/String+EthereumAddress.swift` if other provider packages need address normalization
- `NFTKit/Sources/NFTKit/Support/DecimalQuantityFormatter.swift` if token/RPC packages continue sharing quantity formatting
- `Auralis/Auralis/Networking/AlchemyRPCProvider.swift`
- `Auralis/Auralis/Networking/AlchemyGasPricingProvider.swift`
- the Alchemy transport parts of `NFTKit/Sources/NFTKit/Providers/AlchemyNFTService.swift`
- the Alchemy transport parts of `NFTKit/Sources/NFTKit/Providers/AlchemyTokenHoldingsProvider.swift`

Also move or re-home shared provider failures:

- `NFTKit/Sources/NFTKit/Support/ProviderAbstractionError.swift`
- `NFTKit/Sources/NFTKit/Failures/NFTProviderFailure.swift`
- `NFTKit/Sources/NFTKit/Failures/NFTProviderFailureKind.swift`
- `NFTKit/Sources/NFTKit/Failures/NFTProviderFailurePresentationMode.swift`

Presentation strings can stay app-side or in `NFTKit` if they are truly NFT-specific. The portable error vocabulary belongs in `ProviderKit`.

## Package Boundary

Recommended product:

```swift
.library(name: "ProviderKit", targets: ["ProviderKit"])
```

Recommended dependencies:

- `AuralisPrimaryModels` for `Chain`, `NativeBalance`, `GasPriceEstimate`, token/NFT domain values that are already shared
- `Foundation` only for URL/session/encoding primitives

Avoid dependencies on:

- SwiftUI
- SwiftData
- app target files
- `NFTKit`
- `AgentIdentityCore`
- UI presentation packages

`ProviderKit` should sit below feature packages. `NFTKit`, `ChainProviders`, `ENS`, and `ExplorerAdapter` may depend on it, but it should not depend on them.

## What Belongs Here

- `ProviderEndpointConfiguration`
- `ProviderConfigurationResolving`
- live configuration resolver backed by app secrets/environment
- API-key lookup and validation
- Alchemy base URL construction
- HTTP request execution wrappers
- JSON-RPC envelope/request/response types
- retry policy, jitter/backoff, `Retry-After` parsing
- shared provider transport errors
- provider telemetry hooks that do not depend on receipts or UI
- small test doubles such as `StubProviderConfigurationResolver`

## What Should Stay Out

- SwiftData persistence
- shell lifecycle state
- SwiftUI loading/error presentation
- receipt event recording
- feature-specific orchestration such as `NFTService`
- ENS cache policy
- explorer UI labels and buttons
- account switching or current-chain selection

## Migration Order

1. Create the `ProviderKit` package with only configuration, retry, throttling, and error vocabulary.
2. Move `ProviderConfigurationResolving`, endpoint configuration, secrets, retry parsing, and request throttling out of `NFTKit`.
3. Update `NFTKit` and app networking files to import `ProviderKit`.
4. Move `AlchemyRPCProvider` and `AlchemyGasPricingProvider` into `ProviderKit` without changing behavior.
5. Split Alchemy NFT and token holdings transport so `ProviderKit` owns the HTTP client while `NFTKit` owns inventory orchestration and model persistence.
6. Replace `ReadOnlyProviderFactory` with a composition layer that builds `ProviderKit` clients and hands feature-specific protocols to `NFTKit`/app surfaces.
7. Remove duplicate provider helpers from the app target after builds and tests prove all call sites import the package.

## Public API Shape

Keep protocols capability-oriented:

```swift
public protocol NativeBalanceProviding: Sendable {
    func nativeBalance(for address: String, chain: Chain) async throws -> NativeBalance
}

public protocol GasPricingProviding: Sendable {
    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimateResult
}

public protocol ProviderConfigurationResolving: Sendable {
    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration
}
```

For Alchemy-specific implementation types, prefer explicit names:

- `AlchemyRPCClient`
- `AlchemyGasPricingProvider`
- `AlchemyTokenBalancesClient`
- `AlchemyNFTInventoryClient`

This makes it obvious which code is portable provider infrastructure and which code is one vendor adapter.

## Testing Strategy

Add package-level Swift Testing coverage for:

- configuration resolution for supported and unsupported chains
- missing API-key mapping
- invalid provider URL mapping
- numeric and HTTP-date `Retry-After` parsing
- retry exhaustion and retryable status codes
- RPC envelope decoding for success and error payloads
- native balance hex-to-decimal behavior
- gas pricing fallback behavior if cache stays in the package

Keep integration tests app-side or feature-package-side when they need SwiftData, shell state, or receipts.

## Success Criteria

- UI files no longer import or construct Alchemy network clients directly.
- API-key and endpoint construction code exists in one package.
- `NFTKit` imports `ProviderKit` for provider concerns instead of owning generic provider plumbing.
- Native balance, gas pricing, NFT inventory transport, and token holdings transport share the same configuration and retry vocabulary.
- Provider failures surface as typed errors before reaching UI presentation.
