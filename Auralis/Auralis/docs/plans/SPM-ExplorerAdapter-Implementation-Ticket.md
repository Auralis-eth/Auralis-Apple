# Ticket: Create ExplorerAdapter

## Status

Ready for implementation. This package has no required dependency on `ProviderKit`.

## Goal

Create `ExplorerAdapter`, a local package that builds typed blockchain explorer and marketplace URLs. Views should stop hand-building explorer/OpenSea URLs with string interpolation.

## Source Strategy

Use this with `SPM-ExplorerAdapter-Implementation-Strategy.md`.

## Package To Create

Path:

- `ExplorerAdapter/Package.swift`
- `ExplorerAdapter/Sources/ExplorerAdapter/`
- `ExplorerAdapter/Tests/ExplorerAdapterTests/`

Manifest:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExplorerAdapter",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ExplorerAdapter", targets: ["ExplorerAdapter"]),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
    ],
    targets: [
        .target(
            name: "ExplorerAdapter",
            dependencies: ["AuralisPrimaryModels"]
        ),
        .testTarget(
            name: "ExplorerAdapterTests",
            dependencies: ["ExplorerAdapter"]
        ),
    ]
)
```

Do not depend on `OperatorCore` initially. The app can convert generated URLs into existing operator open requests.

## New Files To Add

- `ExplorerAdapter/Sources/ExplorerAdapter/ExplorerDestination.swift`
- `ExplorerAdapter/Sources/ExplorerAdapter/ExplorerURLBuilding.swift`
- `ExplorerAdapter/Sources/ExplorerAdapter/ExplorerURLBuilder.swift`
- `ExplorerAdapter/Sources/ExplorerAdapter/ExplorerURLBuildError.swift`
- `ExplorerAdapter/Sources/ExplorerAdapter/ExplorerCatalog.swift`
- `ExplorerAdapter/Sources/ExplorerAdapter/OpenSeaDestinationBuilder.swift`

## Public API Requirements

Use this shape unless implementation discovers an existing stronger local convention:

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

public struct ExplorerURLBuilder: ExplorerURLBuilding, Sendable {
    public init(catalog: ExplorerCatalog = .default)
    public func url(for destination: ExplorerDestination) throws -> URL
}
```

Errors:

```swift
public enum ExplorerURLBuildError: Error, Equatable, Sendable {
    case unsupportedChain(Chain)
    case invalidAddress(String)
    case invalidTransactionHash(String)
    case invalidTokenID(String)
    case missingExplorerBaseURL(Chain)
}
```

## Chain Support

Implement deterministic catalog entries for current EVM chains only. Solana chains must return `unsupportedChain` unless explicit Solana explorer support is added in the same ticket.

Do not silently fall back to Ethereum mainnet for any non-mainnet chain.

## App Call Sites To Update

Review and update where URL construction exists:

- `Auralis/Auralis/Aura/Newsfeed/Components/OpenSeaLink.swift`
- NFT detail views that construct marketplace or explorer URLs
- ERC-20 token detail rows/views that construct address/token URLs
- receipt views if transaction/account links already exist

Do not move:

- `ExternalLinkConfirmationSheet`
- actual URL opening
- receipt logging for link opens

## Implementation Steps

1. Create package and manifest.
2. Add destination, error, catalog, and builder types.
3. Add OpenSea NFT builder if `OpenSeaLink` currently builds asset URLs directly.
4. Add package product to the app target.
5. Update call sites to request URLs from `ExplorerAdapter`.
6. Keep existing `OperatorCore`/confirmation flow untouched; only replace URL construction.
7. Add tests.
8. Build app.

## Non-Goals

- Do not fetch explorer metadata.
- Do not open URLs from the package.
- Do not add confirmation UI.
- Do not add receipt logging.
- Do not add provider/API calls.

## Test Requirements

Add table-driven Swift Testing tests for:

- address URL per supported chain
- transaction URL per supported chain
- token contract URL per supported chain
- NFT asset URL per supported chain, if supported
- invalid address rejection
- empty transaction hash rejection
- empty token ID rejection
- Solana unsupported-chain failures
- no mainnet fallback for non-mainnet chains

Tests must not use network access.

## Acceptance Criteria

- `ExplorerAdapter` builds independently.
- Views no longer string-build explorer/OpenSea URLs where this ticket touches them.
- URL opening and confirmation behavior remains unchanged.
- Unsupported chains fail with typed errors.
- Tests cover all supported destination types.

## Rollback Plan

If app call-site migration becomes broad, ship the package and update only `OpenSeaLink` first. Leave other URL construction call sites listed as follow-ups in this ticket.
