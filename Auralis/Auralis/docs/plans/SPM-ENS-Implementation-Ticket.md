# Ticket: Create ENS Package

## Status

Ready for implementation. Provider-backed configuration adapter work should wait until `ProviderKit` exists, but moving core ENS domain out of `AgentIdentityCore` can start now.

## Decision Answer

Do not combine ENS permanently with `AgentIdentityCore`. Create a first-class `ENS` package and move the listed ENS types there. `AgentIdentityCore` may temporarily typealias or re-export ENS types during migration, but the target state is that `ENS` owns ENS.

Do not create a permanent `ENSAdapter` package for these types. They are core ENS domain and implementation, not just adapter glue.

## Source Strategy

Use this with `SPM-ENS-Implementation-Strategy.md`, which records that the `ENS` SPM package is the long-term home for core ENS types.

## Package To Create

Path:

- `ENS/Package.swift`
- `ENS/Sources/ENS/`
- `ENS/Tests/ENSTests/`

Manifest phase 1:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ENS",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ENS", targets: ["ENS"]),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(url: "https://github.com/argentlabs/web3.swift", from: "1.6.1"),
    ],
    targets: [
        .target(
            name: "ENS",
            dependencies: [
                "AuralisPrimaryModels",
                .product(name: "web3.swift", package: "web3.swift"),
            ]
        ),
        .testTarget(
            name: "ENSTests",
            dependencies: ["ENS"]
        ),
    ]
)
```

Phase 2 adds `ProviderKit` when provider-backed configuration moves.

## Files To Move From AgentIdentityCore

Move these into `ENS/Sources/ENS/` preserving subfolders where useful:

- `AgentIdentityCore/Sources/AgentIdentityCore/ENSResolving.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSResolvers.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/EthereumNameServiceClient.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/Web3EthereumNameServiceClient.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/Web3EthereumNameServiceResolver.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/UnavailableEthereumNameServiceClient.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSResolutionCacheStore.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSCacheResetService.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSCacheState.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSForwardCacheEntry.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSForwardResolution.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSReverseCacheEntry.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSReverseResolution.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSResolutionError.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSResolutionProvenance.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSProviderConfiguration.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/ENSEventRecording.swift`
- `AgentIdentityCore/Sources/AgentIdentityCore/NoOpENSEventRecorder.swift`

## Files To Move From App Later

After `ProviderKit` exists:

- `Auralis/Auralis/Networking/AppENSResolvers.swift` -> split into:
  - `ENS/Sources/ENS/Configuration/ProviderBackedENSConfigurationResolver.swift`
  - `ENS/Sources/ENS/Factories/LiveENSResolverFactory.swift`

Do not move yet unless the build already has `ProviderKit`.

Keep app-side for now:

- `Auralis/Auralis/Networking/ReceiptBackedENSEventRecorder.swift`

## Compatibility Plan

Preferred path:

1. Move files to `ENS`.
2. Update direct ENS call sites to `import ENS`.
3. Leave `AgentIdentityCore` depending on `ENS` only if some agent identity code still references ENS types.
4. Add temporary typealiases in `AgentIdentityCore` only if import churn becomes too large.
5. Remove typealiases after all call sites import `ENS` directly.

Do not leave duplicate concrete ENS implementations in both packages.

## Implementation Steps

1. Create `ENS` package.
2. Move ENS files from `AgentIdentityCore` into `ENS`.
3. Update `AgentIdentityCore/Package.swift`: remove `web3.swift` if no remaining file needs it; add dependency on `../ENS` only if compatibility shims are needed.
4. Update app/package imports from `AgentIdentityCore` to `ENS` for ENS-only usages.
5. Build `ENS` package.
6. Build app.
7. Add `ProviderKit` dependency and move `AppENSResolvers.swift` only after ProviderKit is implemented.

## Non-Goals

- Do not redesign ENS resolution semantics.
- Do not persist ENS cache in SwiftData.
- Do not move receipt-backed ENS event logging unless receipt storage/event taxonomy has already been extracted.
- Do not move account identity types into `ENS`.

## Test Requirements

Add `ENSTests` for:

- forward cache hit/miss behavior
- reverse cache hit/miss behavior
- cache expiry if supported by existing store
- cache reset clears forward and reverse entries
- unavailable client throws expected resolution errors
- provenance is preserved for cache and live paths
- provider config mapping tests after `ProviderKit` integration

If existing ENS tests live under app tests, move them into `ENSTests` when they no longer need app-only dependencies.

## Acceptance Criteria

- `ENS` builds independently.
- App builds with ENS call sites importing `ENS`.
- `AgentIdentityCore` no longer directly depends on `web3.swift` unless non-ENS code still needs it.
- No duplicate ENS implementation remains in `AgentIdentityCore`.
- The provider-backed resolver factory is either moved into `ENS` after `ProviderKit`, or explicitly left as the only app-side ENS wiring follow-up.

## Rollback Plan

If the direct move creates too much import churn, keep the new `ENS` package and add temporary `AgentIdentityCore` typealiases. Do not move files back unless `ENS` itself cannot compile.
