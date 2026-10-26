# Final Target Test Ownership Audit

Date: 2026-10-26
Status: Complete for the current 12-package graph

## Rule

Every production target must be a direct dependency of an owning package test target. A target that
exists solely to provide test fixtures may be exempt when the exception is explicit and it contains
no production behavior.

The audit used `swift package dump-package` for every owned package manifest. Direct test-target
dependencies were compared with every regular target; app-level tests were not counted as ownership
evidence for package behavior.

## Results

| Package | Regular targets | Directly covered | Explicit test-support exceptions | Owning test targets |
| --- | ---: | ---: | ---: | --- |
| `AccountsCore` | 20 | 20 | 0 | `AccountsCoreTests`, `AccountStorageTests`, `TokenStorageTests`, `AccountsFeatureTests`, `ProviderKitTests`, `ChainProvidersTests`, `ExplorerAdapterTests`, `ENSTests`, `NFTKitTests`, `WalletConnectorKitTests` |
| `AuraPlayEngines` | 3 | 3 | 0 | One owning suite for each media, audio, and video target |
| `AuraUI` | 1 | 1 | 0 | `AuraUITests` |
| `AuralisFoundation` | 4 | 4 | 0 | One owning suite for each foundation target |
| `AuralisPrimaryModels` | 3 | 2 | 1 | `AuralisPrimaryModelsTests`; `PrimaryModelsTestSupport` is fixture-only |
| `AuralisTestSupport` | 1 | 0 | 1 | Fixture/utility target only; exercised by its package consumers |
| `MissionControlFeature` | 2 | 2 | 0 | `MissionControlFeatureTests`, `TrustedUIKitTests` |
| `OperatorsFeature` | 5 | 5 | 0 | One owning suite for each operator, social, NFT-library, and music target |
| `PolicyCore` | 2 | 2 | 0 | `PolicyCoreTests`, `AutopilotCoreTests` |
| `ReceiptsCore` | 4 | 4 | 0 | One owning suite for each receipt and artifact target |
| `RuntimeCore` | 6 | 6 | 0 | One owning suite for each runtime, planner, playbook, performance, eval, and scheduling target |
| `RuntimeKit` | 3 | 3 | 0 | `RuntimeKitTests`, `AuralisShellCoreTests`, `OperatorRuntimeStorageTests` |
| **Total** | **54** | **52** | **2** | **All production behavior has a direct owner** |

## Explicit Exceptions

### `AuralisTestSupport`

This target contains generic fixtures and test infrastructure. It depends only on
`AuralisFoundation` and system/testing frameworks. Giving it a self-test target would test helpers
rather than product behavior; its real compatibility evidence comes from the package suites that
compile and use it.

### `PrimaryModelsTestSupport`

This target contains `NFTFixture`, which constructs primary domain and persistence models for tests.
It is deliberately separate from generic test support so consumers that do not test NFTs do not gain
a primary-model dependency. It owns no shipping behavior and disappears when the transitional
`AuralisPrimaryModels` package is retired.

## Follow-up Invariant

When a new regular target is added, its manifest change must also add a directly owning test target or
update this audit with a narrow test-support-only exception. Composition and UI tests may supplement
package ownership, but they do not replace it.
