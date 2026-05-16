# ENS Project Memory

## Project Overview

ENS is a local Swift package that provides Ethereum Name Service resolution for Auralis. It handles forward ENS-to-address lookups, reverse address-to-ENS lookups, cache state, provider-backed configuration, and a web3.swift-backed live client.

## Key Architecture Decisions

- `Web3EthereumNameServiceResolver` owns resolution orchestration, cache freshness checks, stale-cache fallback, mapping-change protection, and reverse-lookup forward verification.
- `EthereumNameServiceClient` is the protocol boundary for live ENS calls, keeping resolver tests independent from web3.swift.
- `ENSResolutionCacheStore` owns persisted cache entries and is injected for testability.
- `ProviderBackedENSConfigurationResolver` adapts Auralis provider configuration into ENS endpoint configuration.
- `ENSResolvers` is the composition surface for live and unavailable clients.

## Important Conventions

- Prefer async/await and actor isolation for resolution flows.
- Keep provider configuration errors typed so callers can distinguish missing, invalid, and unavailable provider states.
- Preserve stale-cache fallback behavior when changing network resolution.
- Keep live web3.swift usage behind `EthereumNameServiceClient` so tests can use stubs.

## Build And Run

- Open the ENS package in Xcode or from the parent Auralis workspace.
- Build with the active Xcode scheme or the MCP `BuildProject` tool.
- Run package tests from `Tests/ENSTests`.

## Quirks And Gotchas

- `web3.swift` 1.6.1 depends on `GigaBitcoin/secp256k1.swift` using a broad `0.x` range but expects the old `secp256k1` product name. Newer `secp256k1.swift` releases expose `libsecp256k1` instead, so this package pins `secp256k1.swift` to `0.6.0` at the root.
- The shell sandbox may block command-line SwiftPM writes to `ENS/.build` or `ENS/Package.resolved`; prefer Xcode tools for edits in this environment.
