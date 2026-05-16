# ENS Learning Journal

## The Big Picture

ENS is Auralis's name tag machine for Ethereum. Instead of making people stare at long hexadecimal wallet addresses, it helps translate between human-friendly names like `vitalik.eth` and the addresses the chain actually understands.

## Architecture Deep Dive

Think of the resolver like a careful concierge. A guest asks for a name, the concierge checks the local notes first, calls the outside service only when needed, and refuses to quietly hand out a changed address without raising a flag. The cache is the notebook, the client is the phone line to ENS, and the provider configuration is the directory that tells the concierge which number to dial.

## The Codebase Map

- `Sources/ENS/Web3EthereumNameServiceResolver.swift` is the main resolver brain.
- `Sources/ENS/EthereumNameServiceClient.swift` defines the live-client boundary.
- `Sources/ENS/Web3EthereumNameServiceClient.swift` adapts web3.swift ENS APIs.
- `Sources/ENS/ENSResolutionCacheStore.swift` keeps forward and reverse cache entries.
- `Sources/ENS/ProviderBackedENSConfigurationResolver.swift` bridges Auralis provider configuration into ENS configuration.
- `Tests/ENSTests/ENSResolutionServiceTests.swift` covers cache behavior, typed provider errors, stale fallback, and mapping-change protection.

## Tech Stack & Why

- Swift Package Manager keeps ENS modular and reusable inside Auralis.
- Swift concurrency keeps network lookup flows readable without callback nesting.
- Actors protect resolver state and make cache/network coordination easier to reason about.
- web3.swift supplies ENS primitives so the package does not hand-roll Ethereum name resolution.

## The Journey

### 2026-05-15: The `secp256k1` Product Name Trap

The package failed before it could really get moving: `web3.swift` asked SwiftPM for a product named `secp256k1`, but the resolved `secp256k1.swift` package only offered `libsecp256k1`. This is the package-manager version of ordering from an old menu after the restaurant changed the dish names.

The root cause was a broad transitive dependency range. `web3.swift` 1.6.1 allows `secp256k1.swift` from `0.6.0` up to the next major version, but a later `0.x` release changed the product names anyway. Since `0.x` ecosystems can still move fast, SwiftPM happily picked a version that was technically in range but semantically incompatible.

The fix was to add an explicit root constraint on `GigaBitcoin/secp256k1.swift` at `0.6.0`, the version whose manifest still exposes the `secp256k1` product that `web3.swift` expects. A host `swift build` then got far enough to compile `web3.swift`, but stopped later because a sibling Auralis model package imports `UIKit`; that is an iOS-build limitation, not the original package-resolution failure.

## Engineer's Wisdom

When a transitive dependency breaks on a missing product, inspect both manifests before changing application code. The app usually did nothing wrong; the dependency graph simply resolved a combination the upstream packages did not actually support.

For pre-1.0 packages, treat minor bumps with suspicion. SemVer says `0.x` means the public API may still be unstable, and this incident is a tidy little reminder.

## If I Were Starting Over...

I would isolate third-party ENS/web3 integration behind the same client protocol again, but I would also document transitive dependency pins as soon as we discover them. Future engineers should not need to rediscover the same trap by reading SwiftPM's error message at 1 a.m.
