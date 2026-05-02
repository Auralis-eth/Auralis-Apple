# ARCH-001: Replace `ShellServiceHub` Service Locator With Narrower Dependency Injection

## Goal

Remove `ShellServiceHub` as a dependency passed through presentation code. Keep composition at the app entry point, inject only feature-scoped collaborators, and preserve the existing `ShellStore` state-machine boundary.

## Current State

`ShellServiceHub` is currently doing two jobs at once:

- composition root
- runtime service locator used directly by views and shell wiring

That creates hidden dependency direction across the shell.

### Concrete leakage points

- `MainAuraView` owns infrastructure bootstrap and passes the full hub into child views.
- `MainTabView` reaches into the hub for:
  - account switching
  - context service construction
  - native balance provider creation
  - receipt logging
  - ENS resolution
  - search history
  - token holdings sync
  - music library indexing
- `GatewayView` uses the hub only to get `accountStoreFactory`.
- `HomeTabView` uses the hub only to get `accountStoreFactory`.
- `ProfileDetailView` uses the hub only to create a policy gate.
- `SettingsView` indirectly depends on the same pattern through privacy-reset service creation.
- `ShellStore.live(...)` depends on `ShellServiceHub`, which keeps production shell assembly coupled to the locator shape.

## Target Architecture

### Composition rule

`AuralisApp` or the top-most app composition entry should instantiate live infrastructure once. Views should receive either:

- stable domain/use-case protocols
- already-constructed feature services
- router/state objects they directly render from

Views should not receive factories for unrelated concerns.

### Presentation boundary rule

At the SwiftUI presentation boundary, prefer feature-scoped use cases over infrastructure bags and raw provider factories.

Examples:

- `GatewayView` should depend on account activation and ENS resolution contracts, not app-wide composition state
- `MainTabView` should depend on routed shell state, child feature dependencies, and injected use cases needed to trigger work
- child feature views should receive only the use cases or stores they directly consume

This keeps dependency direction explicit:

- presentation -> feature contract
- feature contract -> infrastructure implementation

not:

- presentation -> service locator -> arbitrary infrastructure

### Keep

- `ShellStore` as the shell state machine
- `AppRouter` as the navigation owner
- long-lived `NFTService`, `ModeState`, `AudioEngine`, and AuraPlay container ownership at the shell bootstrap boundary

### Change

- replace hub-shaped injection with feature-scoped dependency structs and protocols
- move live assembly out of `MainAuraView` and `MainTabView`
- make `ShellServiceHub` either:
  - a private composition-only builder at app entry, or
  - fully deleted once replacement composition types exist

## Recommended Dependency Slices

The main refactor risk is over-correcting into twenty tiny protocols with no ergonomic grouping. Use a small number of feature-scoped dependency bundles, each exposing only its feature contract.

### 1. Shell bootstrap

Create a narrow bootstrap dependency for `MainAuraView`.

Suggested shape:

- `ShellBootstrapDependencies`
  - `makeShellStore(modelContext:nftService:router:) -> ShellStore`
  - `makeGatewayDependencies(modelContext:) -> GatewayDependencies`
  - `makeMainTabDependencies(modelContext:auraPlayModelContainer:) -> MainTabDependencies`

`MainAuraView` should stop knowing how ENS, receipts, providers, or privacy reset services are constructed.

### 2. Gateway

Create `GatewayDependencies`.

Suggested contracts:

- `AccountActivating`
  - persists or activates an entered account
- `ENSResolving`
  - already exists and can stay

`GatewayView` should receive:

- `ensResolver`
- `accountActivator`
- `onAccountActivated`

It should not receive `ShellServiceHub`.

### 3. Shell store assembly

Remove `ShellServiceHub` from `ShellStore.live(...)`.

Suggested approach:

- add `ShellStoreDependencies`
  - `selectionPersistence`
  - `accountResolver`
  - `accountMutator`
  - `refreshCoordinator`
  - `deepLinkReplayer`
  - `routerEffectHandler`
  - `receiptLogger`
  - `clock`
- replace `ShellStore.live(services:modelContext:nftService:router:)` with either:
  - `ShellStore.live(dependencies:)`, or
  - direct construction from `ShellBootstrapDependencies`

This keeps `ShellStore` honest: explicit collaborators in, no factory bag.

### 4. Main tab shell surface

Create `MainTabDependencies`.

Suggested contents:

- `contextService`
- `walletRefreshUseCase`
- `accountSwitching`
- `receiptLogger`
- `searchHistoryStore`
- `tokenHoldingsUseCase`
- `homePinnedItemsStore`
- `libraryContextProvider`
- `musicLibraryIndexer`
- `privacyResetUseCase`
- `policyActionGate`
- `ensResolver`
- `nativeBalanceProvider`

Important detail:
Construct stable stores once when appropriate instead of passing factories everywhere just because the old hub did.

For example:

- `homePinnedItemsStore` can be injected as an instance
- `libraryContextProvider` can be injected as an instance
- `musicLibraryIndexer` can be injected as an instance
- `nativeBalanceProvider` can be injected as an instance

Only keep factories where model-context scoping or short-lived state actually requires them.

### 5. Child feature dependencies

Do not pass `MainTabDependencies` to every child view unchanged. Split again at the presentation boundary:

- `HomeTabDependencies`
  - `accountSummaryLoading`
  - `accountSwitching`
  - `ensResolver`
  - `pinnedItemsStore`
- `ProfileDependencies`
  - `policyActionGate`
- `SettingsDependencies`
  - `privacyResetUseCase`
- `SearchDependencies`
  - `historyStore`
- `ERC20Dependencies`
  - `tokenHoldingsUseCase`

That preserves the rule: composition may group dependencies, presentation gets only what it uses.

## Clarifications Added From Review

The following guidance is now explicit and should be treated as part of the architecture decision:

- `ShellServiceHub` should not be replaced by another wide dependency bag with the same downstream reach
- `MainAuraView` should receive only what it needs to bootstrap shell state and routing, not own infrastructure assembly logic
- `MainTabView` should receive injected use cases, stable feature stores, and routing state instead of reaching into service factories
- use-case naming is preferred at feature boundaries when the dependency represents work, orchestration, or side effects
- stable read models and local state stores may still be injected directly when a protocol wrapper adds no value

## File-Level Implementation Plan

### `AppServices.swift`

1. Introduce the narrow protocols and dependency structs listed above.
2. Move live assembly into explicit builders:
   - `LiveShellBootstrapDependencies`
   - `LiveMainTabDependencies`
   - `LiveGatewayDependencies`
3. Keep existing live factory code initially, but relocate it behind those builders.
4. Limit `AppServices.swift` to composition and adapter code. Do not let presentation-only policy or feature behavior accumulate there.
5. Mark `ShellServiceHub` deprecated during the migration if temporary coexistence helps keep the diff reviewable.
6. Once all call sites are migrated, delete `ShellServiceHub`.

### `MainAuraView.swift`

1. Replace `private let services: ShellServiceHub` with `private let dependencies: ShellBootstrapDependencies`.
2. Remove service construction knowledge from the view initializer.
3. Build:
   - `nftService`
   - `modeState`
   - `ShellStore`
   through bootstrap dependencies instead of direct hub access.
4. Pass `GatewayDependencies` into `GatewayView`.
5. Pass `MainTabDependencies` into `MainTabView`.

### `MainTabView.swift`

1. Replace `let services: ShellServiceHub` with `let dependencies: MainTabDependencies`.
2. In the initializer, stop creating feature services through the locator.
3. Inject stable instances where possible:
   - `homePinnedItemsStore`
   - `libraryContextProvider`
   - `musicLibraryIndexer`
   - `nativeBalanceProvider`
4. Prefer child-facing use-case protocols where work is being triggered, and direct store injection where stable local state is being rendered.
5. Pass narrower child dependencies into:
   - `HomeTabView`
   - `ProfileDetailView`
   - `SettingsView`
   - `SearchRootView`
   - ERC-20 flows
6. Remove all `services.` lookups from the file.

## Safe Migration Order

### Phase 1: Introduce replacement types without behavior change

- add new protocols and dependency structs
- implement live builders using current infrastructure
- keep `ShellServiceHub` intact temporarily

Exit criteria:

- no runtime behavior changes
- compile still green

### Phase 2: Move shell bootstrap off the hub

- change `MainAuraView`
- change `ShellStore.live(...)`
- inject `GatewayDependencies` and `MainTabDependencies`

Exit criteria:

- `MainAuraView` no longer stores `ShellServiceHub`
- `ShellStore.live(...)` no longer accepts `ShellServiceHub`

### Phase 3: Remove main-tab locator access

- migrate `MainTabView`
- migrate child views to narrow dependencies
- eliminate all `services.` usage from presentation code

Exit criteria:

- `MainTabView`, `MainTabSupportViews`, `GatewayView`, `HomeTabView`, `ProfileDetailView`, and `SettingsView` no longer reference `ShellServiceHub`

### Phase 4: Delete or quarantine the locator

- delete `ShellServiceHub`, or keep a private app-entry-only composition wrapper with no logic and no downstream exposure
- update tests and previews to use the new dependency structs directly

Exit criteria:

- `ShellServiceHub` is either gone or private to composition root code

## Testing Plan

### Unit tests

- add tests for live dependency builders where wiring is non-trivial
- replace `ShellServiceHubBoundaryTests` with tests against the new builder/dependency seams
- add focused construction tests for:
  - `ShellStore` live dependencies
  - `MainTabDependencies`
  - privacy reset and policy gate wiring

### Regression checks

- restore shell state from persistence
- activate account from gateway
- switch account and chain from account switcher
- refresh current selection
- open search, profile, and settings flows
- run ERC-20 token sync flow
- run music tab with injected indexer and receipt logger

## Risks To Watch

- accidentally replacing one service locator with three smaller service locators
- turning stable per-shell services into per-render factories
- widening `MainTabDependencies` until it becomes `ShellServiceHub` with a new haircut
- leaking `ModelContext` deeper into presentation code instead of constructing feature collaborators earlier

## Resolved Decisions

The following choices are now part of the plan and should not be re-litigated during implementation PRs unless a concrete blocker appears.

### 1. Exact contract style for feature dependencies

Decision:
Default to use-case protocols for side-effecting or orchestration-heavy work, and allow direct injection for stable read models or local stores.

Rationale:
This matches the current codebase shape, keeps view dependencies explicit, and avoids protocol theater where a stable store is already the natural seam.

Implementation rule:

- use protocols when the dependency triggers work, coordinates multiple collaborators, or performs side effects
- inject the concrete dependency directly when it is already narrow, stable, and primarily rendered or observed by the view

### 2. Permanent home for composition code

Decision:
Keep `AppServices.swift` temporarily as a migration staging area, then split composition code into smaller focused files.

Target split:

- `ShellBootstrapDependencies`
- feature dependency adapters
- live infrastructure builders

Rationale:
This keeps migration churn low now while reducing the long-term risk that `AppServices.swift` becomes the next architecture junk drawer.

### 3. Preview and test construction strategy

Decision:
Define preview/test factories as extensions on each dependency struct in test or preview support areas, not in the main production implementation file.

Recommended shape:

- test-target extensions providing `testValue`
- preview-support extensions providing `preview`

Rationale:
This keeps production dependency types clean while still making fake wiring terse and discoverable.

## Dependency Ownership Policy

This decision is now part of the plan.

### Rule

Document dependency ownership explicitly and encode lifetime in the dependency shape wherever possible.

Use both of these mechanisms together:

- keep an ownership table in this document so reviews have a shared vocabulary
- make the code reflect lifetime directly instead of relying on comments alone

### Lifetime rules

- app-scoped dependencies are created once at app/bootstrap level
- shell-scoped dependencies are stored properties on the shell/bootstrap dependency builder
- model-context-scoped dependencies are factories that receive or capture the current `ModelContext`
- feature-scoped dependencies are created inside the feature boundary or injected into that feature only

Long-lived shell dependencies should be stored instances. Factory closures should be reserved for dependencies that are genuinely context-scoped or feature-created.

### Code review test

If a dependency is exposed as a factory, reviewers should ask:

`What changing context or lifetime requires this to be recreated?`

If the answer is `nothing`, it probably should not be a factory.

### Ownership table

| Dependency | Owner | Lifetime | Creation site |
| --- | --- | --- | --- |
| `ReadOnlyProviderFactory` | App/bootstrap composition | App-scoped | App entry or top-level live builder |
| `ModeState` | Shell bootstrap | Shell-scoped | `ShellBootstrapDependencies` live builder |
| `NFTService` | Shell bootstrap | Shell-scoped | `ShellBootstrapDependencies` live builder |
| `AppRouter` | Shell bootstrap | Shell-scoped | `MainAuraView` bootstrap path |
| `ShellStore` | Shell bootstrap | Shell-scoped | `makeShellStore(...)` |
| `ENSResolving` for a shell session | Shell bootstrap or feature builder | Model-context-scoped | `makeGatewayDependencies(modelContext:)` or equivalent |
| `AccountActivating` / `AccountStore` | Feature dependency builder | Model-context-scoped | `GatewayDependencies` / `HomeTabDependencies` builder |
| `HomePinnedItemsStore` | Main tab dependencies | Shell-scoped | `makeMainTabDependencies(...)` |
| `SearchHistoryStore` | Main tab dependencies | Model-context-scoped | `makeMainTabDependencies(...)` |
| `TokenHoldingsUseCase` and backing stores/providers | Main tab or ERC-20 feature builder | Mixed: shell-scoped orchestrator plus model-context-scoped storage where needed | `makeMainTabDependencies(...)` / `ERC20Dependencies` builder |
| `PolicyActionGate` | Profile feature builder | Model-context-scoped | `ProfileDependencies` builder |
| `PrivacyResetUseCase` | Settings feature builder | Model-context-scoped | `SettingsDependencies` builder |

This table is intentionally small. Add new rows when introducing new dependency slices that are not obvious from the existing entries.

## Writer Handoff

The writer should treat the following as settled:

- `ShellServiceHub` is an anti-pattern in presentation code and must not survive the migration in any view-facing form
- feature boundaries should prefer use-case protocols for side-effecting work and direct injection for narrow stable stores
- `AppServices.swift` is temporary migration scaffolding, not the final architecture destination
- dependency lifetime is part of the design, not an implementation afterthought
- factories require a lifetime/context reason; otherwise inject stored instances

The main implementation ambiguity left to the coding pass is naming and exact protocol surface area, not architecture direction.
## Review Checklist

- no SwiftUI view accepts `ShellServiceHub`
- no SwiftUI view accepts unrelated factories “just in case”
- `ShellStore` live assembly is explicit and testable
- model-context-scoped collaborators are created once per feature boundary where appropriate
- previews and tests can substitute dependencies without using production live builders
- dependency direction is presentation -> use case/protocol, never presentation -> infrastructure bag

## Recommended First PR

Keep the first implementation PR intentionally narrow:

1. add `ShellBootstrapDependencies`, `GatewayDependencies`, `MainTabDependencies`, and `ShellStoreDependencies`
2. migrate `MainAuraView` and `ShellStore.live(...)`
3. leave child view narrowing for the next PR

That breaks the biggest architectural back-edge first without forcing a risky all-shell rewrite in one review.
