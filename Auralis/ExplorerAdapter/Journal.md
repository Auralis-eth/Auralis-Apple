# ExplorerAdapter Journal

## The Big Picture

ExplorerAdapter is the small, sturdy signpost layer for Auralis. Given a chain, wallet, contract, transaction, or NFT token, it builds the right block-explorer or marketplace destination instead of making the app scatter URL recipes everywhere.

## Architecture Deep Dive

Think of it like a concierge desk in a large venue. The rest of the app says, "I need to see this address on Base," and ExplorerAdapter knows which door to point to, how the address should be shaped, and when to say "that route does not exist." The catalog keeps the map, builders create the destination, and explicit errors keep bad handoffs from turning into mysterious browser failures.

## The Codebase Map

- `Sources/ExplorerAdapter/ExplorerCatalog.swift` keeps explorer metadata and supported hosts.
- `Sources/ExplorerAdapter/ExplorerURLBuilder.swift` builds block-explorer URLs for addresses, transactions, tokens, and NFTs.
- `Sources/ExplorerAdapter/OpenSeaDestinationBuilder.swift` builds OpenSea asset destinations for supported chains.
- `Sources/ExplorerAdapter/ExplorerDestination.swift` defines the destination requests the rest of the app can ask for.
- `Tests/ExplorerAdapterTests/` verifies chain coverage, URL shapes, labels, and invalid-input failures.

## Tech Stack & Why

This is a Swift Package because explorer-link behavior is small, portable domain logic that should be testable without launching the full app. It depends on `AuralisPrimaryModels` so chain identity stays shared with the rest of Auralis instead of being copied into another enum.

Swift Testing is used for the unit tests because parameterized tests make the chain matrix readable: one test describes the behavior, and the data table carries the explorer-specific cases.

## The Journey

### 2026-05-15: Private Data Meets Parameterized Tests

The test suite used a private `ExplorerCase` helper to feed several parameterized Swift Testing methods. Swift was rightfully strict: a test method that is visible outside its private helper type cannot accept that private type as a parameter. The fix was to make those parameterized test methods private too, keeping the helper table tucked inside the suite while preserving the readable parameterized coverage.

The follow-on missing `.swiftmodule`, `.swiftdoc`, `.swiftsourceinfo`, and `.abi.json` messages were build artifacts that did not get produced because compilation stopped early. Once the source visibility issue is fixed, those should disappear with the next clean build.

## Engineer's Wisdom

Visibility is part of an API contract, even inside tests. If a private fixture type is only meant for one suite, keep the tests that accept it at the same privacy level. That keeps the suite self-contained without promoting helper types just to appease the compiler.

Parameterized tests are still the right tool here: they keep the explorer matrix in one obvious place and prevent twenty near-identical tests from drifting apart.

## If I Were Starting Over...

I would keep the chain-case table private from day one and mark the parameterized test methods private at the same time. The pattern is simple once seen: private arguments imply private test entry points.
