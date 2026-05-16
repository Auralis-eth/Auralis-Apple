# AgentIdentityCore Journal

## The Big Picture

AgentIdentityCore is the small identity-facing package in the Auralis constellation. Think of it as the front desk for agent identity work: modest today, but positioned where wallet identity, ENS lookup, and higher-level app flows can meet without dragging the whole app target into every conversation.

## Architecture Deep Dive

Right now the package is deliberately thin. `AgentIdentityCore` depends on the local `ENS` package, which is like sending name-resolution questions to a specialist instead of making the front desk memorize the entire phone book. That keeps identity code free to grow while ENS keeps its own networking and web3 concerns behind its package boundary.

## The Codebase Map

- `Package.swift` declares the package, its iOS platform floor, and package dependencies.
- `Sources/AgentIdentityCore/AgentIdentityCore.swift` currently holds the public package marker type.
- `Package.resolved` pins the dependency graph Xcode and SwiftPM should resolve for this package.

## Tech Stack & Why

- Swift Package Manager gives this feature a clean module boundary inside the larger Auralis workspace.
- Swift 6 keeps the package aligned with the app's modern Swift direction.
- The local `ENS` package is reused because ENS resolution is already a separate capability and should not be reimplemented here.

## The Journey

### 2026-05-16: The Case of the Renamed secp256k1 Product

Xcode reported that `web3.swift` wanted a product named `secp256k1`, but the resolved `secp256k1.swift` package only offered `libsecp256k1`. The dependency graph had wandered to `secp256k1.swift` `0.23.1`, while `web3.swift` `1.6.1` expects the older product layout.

The fix was to pin `secp256k1.swift` to `0.6.0` in `AgentIdentityCore`, matching the local `ENS` package's constraint, then update `Package.resolved` to the `0.6.0` revision. In kitchen terms: the recipe expected the old spice jar label, so we put the pantry back on the shelf that recipe was written for.

## Engineer's Wisdom

Package-resolution bugs often look like source errors, but the source may be innocent. Check the manifest and lockfile together: a correct `Package.swift` with a stale `Package.resolved` can still send Xcode down the wrong hallway.

## If I Were Starting Over...

I would keep shared web3 dependency constraints close to the package that opens in Xcode, even when a local dependency already declares the same constraint. Xcode package workspaces can be sensitive to the root package's resolved graph, so being explicit at the entry point makes the dependency contract easier to see and harder to drift.
