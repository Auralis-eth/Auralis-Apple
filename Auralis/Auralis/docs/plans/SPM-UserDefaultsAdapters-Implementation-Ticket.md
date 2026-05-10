# Ticket: Create UserDefaultsAdapters

## Status

Defer until at least two stores can share the generic helper. Do not create this package just to move one feature-local store.

## Goal

Create `UserDefaultsAdapters`, a small package for reusable Codable/UserDefaults key-value storage primitives. It should support feature-local stores such as pinned home actions and search history without owning feature-specific records or action enums.

## Source Strategy

Use this with `SPM-StorageAdapters-Implementation-Strategy.md`.

## Package To Create

Path:

- `UserDefaultsAdapters/Package.swift`
- `UserDefaultsAdapters/Sources/UserDefaultsAdapters/`
- `UserDefaultsAdapters/Tests/UserDefaultsAdaptersTests/`

Manifest:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UserDefaultsAdapters",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "UserDefaultsAdapters", targets: ["UserDefaultsAdapters"]),
    ],
    targets: [
        .target(name: "UserDefaultsAdapters"),
        .testTarget(
            name: "UserDefaultsAdaptersTests",
            dependencies: ["UserDefaultsAdapters"]
        ),
    ]
)
```

## Candidate Extraction Sources

Use these to identify shared patterns, not to move wholesale:

- `Auralis/Auralis/Aura/Home/HomePinnedItemsStore.swift`
- `Auralis/Auralis/Aura/Search/SearchHistoryStore.swift`

Move only generic helpers, such as:

- encode/decode `[Record]` to `UserDefaults.data(forKey:)`
- corrupt-payload recovery policy
- remove key
- scoped test `UserDefaults` suite creation if repeated

Keep app-side:

- `HomePinnedItemRecord`
- `HomePinnedItemsStore`
- `HomeLauncherAction`
- search-specific record ranking/history policy
- UI-facing error copy

## Public API Requirements

Suggested generic helper:

```swift
public struct UserDefaultsCodableStore<Record: Codable & Sendable>: Sendable {
    public init(
        userDefaults: UserDefaults,
        key: String,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        corruptionPolicy: CorruptionPolicy = .returnEmptyAndClear
    )

    public func load() throws -> [Record]
    public func save(_ records: [Record]) throws
    public func clear()
}

public enum CorruptionPolicy: Sendable {
    case throwError
    case returnEmptyAndClear
}
```

Adjust names to compile with Swift `Sendable` constraints; do not over-engineer generic abstractions beyond current needs.

## Implementation Steps

1. Confirm both Home pinned items and Search history can use the same helper without moving feature policy.
2. Create package and manifest.
3. Add `UserDefaultsCodableStore` and corruption error types.
4. Refactor one store at a time to use the helper internally while keeping its public API unchanged.
5. Add package product to app target.
6. Add tests for helper and affected feature stores.
7. Build.

## Non-Goals

- Do not move feature-specific stores into this package.
- Do not change pinned item limits, search history ranking, or account scoping policy.
- Do not add SwiftUI.
- Do not import `AuralisPrimaryModels` unless the helper truly needs shared model types.

## Test Requirements

Add package tests for:

- save and load Codable records
- missing key returns empty array
- clear removes data
- corrupt payload throws when policy is `.throwError`
- corrupt payload returns empty and clears key when policy is `.returnEmptyAndClear`

Add app tests or update existing tests for:

- `HomePinnedItemsStore` still preserves max pinned count
- `SearchHistoryStore` behavior remains unchanged, if migrated

## Acceptance Criteria

- `UserDefaultsAdapters` exists only if at least two app stores use it or are ready to use it.
- Generic helper has no feature-specific knowledge.
- Home/search public behavior remains unchanged.
- Corrupt payload behavior is explicit and tested.

## Rollback Plan

If only one store can use the helper cleanly, do not create the package. Leave the ticket deferred and keep the store local until a second consumer appears.
