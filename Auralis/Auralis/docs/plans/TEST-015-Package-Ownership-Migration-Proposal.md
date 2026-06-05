# TEST-015 Package Ownership Migration Proposal

## Purpose

TEST-015 exists because several local Swift packages own important production behavior while most of their meaningful tests still live in `AuralisTests`. That makes the app test target look healthy, but it leaves package refactors under-protected. The goal is to move behavioral coverage to the package that owns the behavior, while keeping only true app-composition tests in the app target.

This proposal covers the broader migration that was intentionally left out of the Phase 3 container and edge-case cleanup.

## Recommendation

Move coverage in slices by package boundary, not by copying whole test files wholesale. Some current app tests mix package behavior with app-only adapters, SwiftData app schemas, receipt storage, or shell composition. Those should be split first so the package-owned assertions can move cleanly and the app-owned integration contracts can remain in `AuralisTests`.

Recommended order:

1. Fix package test execution prerequisites.
2. Move pure package behavior tests first.
3. Split mixed app/package tests into package unit tests plus small app integration tests.
4. Add missing package behavior tests where no app test exists to move.
5. Update CI/test plans so package tests are first-class and filtered by shared tags.

## Current Ownership Map

| Behavior | Current app-test source | Owning package | Recommendation |
|---|---|---|---|
| NFT refresh state, provider failure presentation, metadata parsing/prep | `NFTRefreshStateComputerTests`, `NFTProviderFailurePresentationTests`, `NFTMetadataUpdaterTests`, `PrepareNFTMetadataUseCaseTests` | `NFTKit` | Move directly after adding test dependencies. These are package-owned and should not need app imports. |
| NFT inventory fetch/persist/service orchestration | `FetchNFTInventoryUseCaseTests`, `PersistNFTInventoryUseCaseTests`, `NFTServiceTests`, parts of `NFTServiceReceiptTests` | `NFTKit` plus app receipt adapters | Split. Move provider/persistence/service behavior to `NFTKit`; keep receipt-backed app adapter coverage in `AuralisTests`. |
| Music presentation and domain formatting | `MusicCollectionPresentationTests`, `MusicItemDetailPresentationTests` | `MusicFeature` | Move directly. These should become package presentation contract tests. |
| Music library indexing and receipts | `MusicLibraryIndexTests`, `MusicReceiptEventLoggerTests` | `MusicFeature` plus app container wiring | Split. Move `MusicReceiptEventLogger` behavior and AuraPlay persistence tests to `MusicFeature`; keep cross-store app composition if it depends on the primary app container. |
| Color helpers, theming primitives, motion/layout helpers | portions of `HelperConsistencyTests`, missing package coverage | `AuraUI` | Add package-local tests. Do not keep parity tests in the app target once AuraUI owns the public contract. |
| Scanner scan mode and QR validation | `CodeScannerTests` already package-local | `CodeScanner` | Extend existing tests with camera-free state/validation contracts. No app target move needed unless app has scanner-specific assertions elsewhere. |
| Chain/domain values and SwiftData primary persistence values | `ChainTests`, `EOAccountTests`, parts of `HelperConsistencyTests` | `AuralisPrimaryModels` / `AuralisPrimaryPersistence` | Move domain and model behavior to package tests. Keep only app schema assembly tests in `AuralisTests`. |
| Account validation and account-store protocols | `AccountStoreTests`, package-local `AccountsCoreTests`, storage tests | `AccountsCore` / `AccountStorage` | Keep validation/protocol tests in `AccountsCore`; keep SwiftData-backed persistence tests in `AccountStorage`; keep app assembly/receipt recorder integration in `AuralisTests`. |
| Provider configuration, retry, Alchemy services | `ProviderAbstractionTests` | `ProviderKit` and NFT/provider adapter packages | Split by provider type. Move provider clients to `ProviderKit`; move NFT fetcher-specific retry/pagination behavior to `NFTKit/NFTProviderAdapters`. |

## Preconditions

### 1. Package Test Execution Must Be Fixed

Current direct `swift test` runs are blocked by package manifest/platform issues. The observed failure is that some packages default to macOS 10.13 while depending on products that require macOS 15.0. Before TEST-015 can be considered complete, each touched package should declare platforms compatible with its dependencies.

Recommended manifest cleanup:

- Add explicit `.macOS(.v15)` or higher to `AccountStorage`, `TokenStorage`, `ReceiptStorage`, and `AccountsCore` if they depend on `AuralisPrimaryModels`, `AuralisPrimaryPersistence`, `ProviderKit`, or `ReceiptsCore` products that require macOS 15.0.
- Keep iOS platform declarations aligned with the app and package dependencies.
- Run `swift test --disable-sandbox --package-path <Package>` as a local fallback only when the harness sandbox blocks manifest compilation; CI should run normal package tests.

### 2. Shared Test Support Must Stay Dependency-Clean

`AuralisTestSupport` can provide generic test helpers, shared tags, deterministic dates, and package-neutral fixtures. It should not import app-only targets.

Recommended additions:

- `AuralisTestSupport` fixtures for public domain values that are legal to share, such as addresses, dates, chain values, and raw provider payloads.
- Package-local test support files for SwiftData schemas that cannot be centralized without introducing illegal dependencies.
- Package-local mock URL sessions or provider doubles when they depend on package internals.

### 3. App Integration Tests Should Become Explicit

After moving package behavior tests, the app target should keep only tests that prove wiring across boundaries:

- app assemblies build live collaborators
- receipt-backed adapters bridge package events into app receipt storage
- shell/router/app SwiftData composition uses the right package services
- release/test-plan architecture scanners remain in the architecture lane

## Migration Slices

### Slice 1: NFTKit Pure Behavior

Move first because the package already has separate targets for domain, provider adapters, persistence, and presentation.

Move or split into `NFTKit/Tests/NFTKitTests/`:

- `NFTRefreshStateComputerTests.swift`
- `NFTProviderFailurePresentationTests.swift`
- `NFTMetadataUpdaterTests.swift`
- `PrepareNFTMetadataUseCaseTests.swift`
- package-owned parts of `FetchNFTInventoryUseCaseTests.swift`
- package-owned parts of `PersistNFTInventoryUseCaseTests.swift`

Package manifest changes:

- Expand `NFTKitTests` dependencies from `NFTDomain` and `NFTKit` to include specific internal targets under test: `NFTProviderAdapters`, `NFTPersistence`, `NFTPresentation`, and any legal test-support dependency.
- Prefer importing the concrete target under test instead of the umbrella `NFTKit` module when testing layer boundaries.

Keep in app target:

- receipt-backed refresh recorder integration with app receipt storage
- app-specific `NFTService` wiring if it touches app-only collaborators

Validation:

- `swift test --package-path NFTKit --filter NFTKitTests`
- Xcode `BuildProject`
- App tests for remaining receipt-backed integration

### Slice 2: MusicFeature Behavior

Move presentation and receipt logger behavior after NFTKit because MusicFeature has fewer target layers but includes SwiftUI and persistence.

Move or split into `MusicFeature/Tests/MusicFeatureTests/`:

- `MusicCollectionPresentationTests.swift`
- `MusicItemDetailPresentationTests.swift`
- `MusicReceiptEventLoggerTests.swift`
- package-owned parts of `MusicLibraryIndexTests.swift`

Keep in app target:

- any test that proves the app primary container and AuraPlay container are composed together correctly
- app shell navigation into MusicFeature
- live app assembly smoke tests

Recommended new package-local support:

- `MusicFeatureTestModelContainers` for `AuraPlaySchema`
- deterministic media item fixtures
- in-memory receipt store doubles if the test only checks `MusicReceiptEventLogger` payloads

Validation:

- `swift test --package-path MusicFeature --filter MusicFeatureTests`
- focused app tests for music assembly and shell integration

### Slice 3: Provider Tests Split Out Of `ProviderAbstractionTests`

`ProviderAbstractionTests.swift` is too broad and should not move as one file.

Recommended package files:

- `ProviderKit/Tests/ProviderKitTests/ProviderConfigurationResolverTests.swift`
- `ProviderKit/Tests/ProviderKitTests/RetryAfterSupportTests.swift`
- `ProviderKit/Tests/ProviderKitTests/AlchemyRPCProviderTests.swift`
- `ProviderKit/Tests/ProviderKitTests/AlchemyDataAPIServiceTests.swift`
- `NFTKit/Tests/NFTProviderAdaptersTests/NFTFetcherRetryTests.swift` if a separate test target is added, or keep under `NFTKitTests` with a clear suite name.

Keep in app target:

- tests that prove app provider assembly selects the right live provider based on app configuration
- receipt/logging tests that cross from provider failures into app receipt storage

Recommendation:

Do not move all provider tests in the same PR as NFTKit or MusicFeature. The file is large, strict-concurrency-sensitive, and already has a mix of URL loading, provider error mapping, retry delay, pagination, and presentation behavior.

### Slice 4: AuraUI, CodeScanner, AuralisPrimaryModels, AccountsCore

These are smaller but should be handled deliberately.

AuraUI:

- Add tests for public color hex helpers, theming primitives, motion policy helpers, and layout modifiers.
- Move any `HelperConsistencyTests` assertions that compare AuraUI behavior into `AuraUI/Tests/AuraUITests/`.

CodeScanner:

- Extend existing package-local `ScanMode` coverage.
- Add QR/address validation tests only if the validation helper is actually owned by `CodeScanner`; otherwise keep address validation in `AccountsCore` or app scanner integration.

AuralisPrimaryModels:

- Move `ChainTests`, `EOAccountTests`, and pure primary model assertions out of `AuralisTests`.
- Keep app schema membership checks in app architecture tests.

AccountsCore:

- Keep address input validation and error description tests package-local.
- Do not move SwiftData persistence tests into `AccountsCore`; those belong to `AccountStorage`.

## App Target Cleanup After Moves

After each package migration:

1. Delete the moved app test file only after the package test passes.
2. If a mixed file was split, rename the remaining app test to show its integration scope, for example `NFTRefreshReceiptIntegrationTests.swift`.
3. Remove now-unused app test fixtures from `AuralisTests`.
4. Run scans:

```bash
rg "NFTMetadataUpdaterTests|NFTServiceTests|MusicCollectionPresentationTests|ProviderAbstractionTests|HelperConsistencyTests" AuralisTests
rg "String\(describing:.*\.self\).*==" --glob '*Tests*.swift'
rg "@Suite\s*$" --glob '*Tests*.swift'
```

Remaining matches in `AuralisTests` should be app integration suites, not package behavior suites.

## CI And Test Plan Changes

TEST-015 should not be considered complete until CI treats package tests as first-class.

Recommended lanes:

- Fast app unit lane: app target tests, excluding `.slow` and `.architecture`.
- Package unit lane: all local package tests, excluding `.slow` unless explicitly requested.
- Architecture lane: `.architecture` suites and package-boundary scanners.
- Slow/integration lane: receipt integrity, filesystem scanners, longer async/retry suites.

Package tests should use the shared `Tag` vocabulary from `AuralisTestSupport` where legal. If a package cannot depend on `AuralisTestSupport` without dependency pollution, define no tags there rather than importing the wrong layer.

## Acceptance Checklist

TEST-015 can close when all of these are true:

- [ ] `NFTKit` owns tests for NFT metadata, refresh state, inventory fetch, inventory persistence, metadata prep, and NFT provider adapter retry/pagination behavior.
- [ ] `MusicFeature` owns tests for music presentation, AuraPlay media persistence/indexing, and music receipt event payloads.
- [ ] `AuraUI` owns tests for public color/theming/motion/layout helper behavior.
- [ ] `CodeScanner` owns camera-free scanner state and validation tests.
- [ ] `AuralisPrimaryModels` owns primary domain and persistence model behavior tests.
- [ ] `AccountsCore` owns account validation/protocol behavior tests, while `AccountStorage` owns SwiftData-backed account persistence tests.
- [ ] App tests that remain are explicitly integration/composition tests by name and imports.
- [ ] Package manifests can run `swift test` directly without platform mismatch failures.
- [ ] CI runs local package tests as a required lane.
- [ ] The app test target no longer contains package-owned behavior suites except documented integration wrappers.

## Risks And Mitigations

Risk: moving tests exposes production types that are currently internal to the app target.

Mitigation: do not widen access just for tests until ownership is clear. Prefer moving the production type into the owning package first, then move the test.

Risk: package tests start importing app modules to keep old fixtures working.

Mitigation: reject app imports from package tests. Replace fixtures with package-local builders or `AuralisTestSupport` helpers that do not depend on app code.

Risk: one giant PR moves hundreds of assertions and makes regressions hard to review.

Mitigation: use one package or one behavior family per PR. Each PR should delete or shrink a named app test file and add package tests that can run independently.

Risk: SwiftData schemas diverge between package tests and app tests.

Mitigation: package tests should use package-local schema helpers for package-owned models. App integration tests should use `TestModelContainers` and `PrimaryStoreSchema`.

## Suggested PR Sequence

1. `test-refactor-package-platforms`: fix package platform declarations so package tests run directly.
2. `test-refactor-nftkit-pure-tests`: move NFT metadata, refresh state, and prep tests.
3. `test-refactor-nftkit-inventory-tests`: move fetch/persist/retry tests and split app receipt integration.
4. `test-refactor-musicfeature-tests`: move music presentation, media indexing, and receipt logger tests.
5. `test-refactor-providerkit-tests`: split provider configuration/RPC/data API tests out of `ProviderAbstractionTests`.
6. `test-refactor-primarymodels-auraui-tests`: move model and UI helper behavior from app parity tests.
7. `test-refactor-final-app-integration-names`: rename remaining app suites to make integration ownership explicit and update CI/test plans.

## Recommended First Slice

Start with `NFTRefreshStateComputerTests`, `NFTProviderFailurePresentationTests`, `NFTMetadataUpdaterTests`, and `PrepareNFTMetadataUseCaseTests` into `NFTKit`. These should have the least app-only coupling and will prove the package-test lane, dependency declarations, and fixture strategy before touching heavier SwiftData or provider retry suites.
