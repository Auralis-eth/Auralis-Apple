# ARCH-003: Domain Package Consolidation Plan

Status: Complete — roots and internal targets both consolidated
Date: 2026-10-27 (revised from 2026-10-26, 2026-09-09)
Supersedes nothing. Extends `ADR-008-operator-runtime-package-boundaries.md`.
Related: `ARCH-004-Independent-Core-And-Adapter-Migration-Plan.md`, `TEST-015-Package-Ownership-Migration-Proposal.md`, `ADR-011-app-composition-boundaries.md`, `ADR-012-nft-refresh-pipeline.md`.

Completion record: the repository contains exactly **12 Auralis-owned Swift package roots plus
vendored `CodeScanner`**, and those roots declare **29 targets where they once declared 113**.

## 2026-10-27 revision: one module per package

The "fewer packages, not fewer boundaries" principle stated below was **deliberately reversed** on
2026-10-27. The goal is now one SPM package producing one framework. Ten of the twelve owned packages
are exactly one library plus one test target; the exceptions are enumerated and each has a reason
SwiftPM forces:

| Package | Extra product | Why it cannot merge |
|---|---|---|
| `AuralisCrypto` | `WalletAdapters` | SwiftPM conditions *dependencies* per platform but not *source files*. The iOS-gated vendor adapters would compile on macOS against SDKs that are not linked there. It also stops every consumer of a plain `Chain` or `EOAccount` from linking five wallet SDKs. |
| `AuralisCrypto` | `AuralisCryptoTestSupport` | Fixtures consumed by `AuralisOperators`' tests, which must not link into production. |
| `AuraPlayEngines` | two demo executables | Executables, not frameworks. |

Consequences accepted with the reversal, recorded so they are not later "fixed" as regressions:

- **One platform floor.** Every owned package declares iOS 26 / macOS 26. The former split (reusable
  cores at iOS 18 / macOS 15, UI and composition at 26) cannot survive one module per package,
  because SwiftPM applies platform declarations to the whole package and a single module holds both
  a SwiftUI surface and the core it used to sit above.
- **Intra-package layering is no longer import-checkable.** Rules that separated `AuralisPrimaryModels`
  from `NFTKit`, or `ReceiptsCore` from `ReceiptStorage`, described modules that are now one module.
  Those assertions were removed rather than left passing vacuously; see the note in
  `ArchitectureBoundaryTests`. Layering is now carried by the source-group structure under each
  package's `Sources/<Module>/` directory, and by the product-list and retired-root guards.
- **Renames.** `AccountsCore`→`AuralisCrypto`, `RuntimeCore`→`AuralisRuntime`,
  `RuntimeKit`→`AuralisAppShell`, `ReceiptsCore`→`AuralisReceipts`,
  `OperatorsFeature`→`AuralisOperators`, `PolicyCore`→`AuralisPolicy`,
  `MissionControlFeature`→`AuralisMissionControl`.

The historical inventory below remains as the migration baseline.

## Purpose

Auralis currently has **42 local Swift package roots**—41 Auralis-owned plus vendored
`CodeScanner`—and **193 Swift files still in the app target** (2026-10-22 inventory).
The package count grew one concern at a time, which was correct while the runtime kernel was being
discovered, but it now costs more than it protects: manifest churn, 40+ `Package.resolved` entries,
unclear ownership for new code, and an app target that still holds whole domains (Context, Receipts UI,
Wallet Connection, Social) with no package boundary at all.

This plan consolidates the local graph into a **small set of domain-owned packages**, each with
internal targets that preserve the layering ADR-008 already enforces.

The goal is *fewer packages, not fewer boundaries*: **12 Auralis-owned Swift packages**, plus the
vendored `CodeScanner` package and ordinary third-party dependencies. `CodeScanner` and external
packages are deliberately excluded from the 12-package count.

The architectural fit is Clean Architecture at package scale: domain contracts and models point
inward; persistence, network, provider, vendor-SDK and UI implementations point toward those
contracts; the app shell is the composition root. Internal targets—not additional package roots—are
the principal enforcement mechanism.

This revision is grounded in the 2026-09-29 Sovereign Human Agent Strategy, the 2026-10-13 Executive
Function Operating System thesis, and a 2026-10-22 source inventory. It treats the human as principal
and preserves the distinction between capability, authority, policy, execution and evidence.

## Canonical Concept Boundaries

| Concept | Definition | Architectural invariant |
|---|---|---|
| Intent | An expressed or inferred desired outcome, including source and degree of authorization. | An inferred intent never silently becomes an authorized commitment. |
| Plan | A proposed approach, including steps, dependencies and alternatives. | A plan cannot grant itself execution authority. |
| Commitment | A durable, authorized obligation pursued until resolved, cancelled, delegated or renegotiated. | It survives individual executions and closes only against its success criteria. |
| Runtime state | Operational state of an execution: progress, retries, suspension, errors and cancellation. | Execution success does not automatically fulfill a commitment. |
| Memory | Durable knowledge, preferences, history and user-approved retained information. | Context cannot silently become permanent memory. |
| Context | A task-specific, time-sensitive assembly of memory, live observations and provenance. | Context is assembled for a decision and has explicit freshness/governance rules. |
| Artifact | A durable output or resource such as a document, plan, draft or evidence file. | Artifacts may reference receipts but are not receipts. |
| Receipt | An auditable record of a consequential decision, authorization, action, denial or outcome. | A receipt is evidence; an outcome verifier interprets evidence against commitment criteria. |

Revocation prevents further unauthorized execution regardless of memory or context contents.

---

## Current State

### Local package roots (43: 42 owned + CodeScanner)

`AuralisFoundation` was added on 2026-10-23 as the first destination package. The temporary root
increase is intentional: source owners move into their final package before the mixed
`AuralisPrimaryModels` root can be deleted. The consolidation target remains 12 owned roots.

| Group | Packages |
|---|---|
| Foundation / shared | `AuralisFoundation`, `AuralisPrimaryModels` (2 targets), `SwiftDataAdapters`, `UserDefaultsAdapters`, `AuraUI`, `AuralisTestSupport`, `CapabilitiesCore` |
| Runtime kernel | `RuntimeCore`, `PlannerCore`, `PlaybookCore`, `SchedulingCore`, `PerformanceCore`, `EvalCore`, `SocialCore`, `OperatorRuntimeStorage`, `RuntimeKit` |
| Policy | `PolicyCore`, `AutopilotCore` |
| Receipts / artifacts | `ReceiptsCore`, `ReceiptStorage`, `ArtifactCore`, `ArtifactStorage` |
| Crypto / Web3 | `AccountsCore`, `AccountStorage`, `AccountsFeature`, `ChainProviders`, `ProviderKit`, `ENS`, `ExplorerAdapter`, `TokenStorage`, `WalletConnectorKit` (6 products), `NFTKit` (5 products) |
| Operators / features | `OperatorCore`, `OperatorsFeature`, `MusicFeature`, `NFTLibraryFeature`, `MissionControlFeature`, `TrustedUIKit`, `AuralisShellCore` |
| Media engines | `AuraPlayMediaCore`, `AuraPlayAudioEngine`, `AuraPlayVideoEngine` |
| Vendored | `CodeScanner` |

### App target residue (193 files, by domain)

| Area | Files | Has a package today? |
|---|---|---|
| `Context*.swift` + `LiveContextSource` (root) | 16 | **No** |
| `Receipts/` (timeline, detail, payload views, logging) | 21 | Partly (`ReceiptsCore`/`ReceiptStorage`) |
| `Aura/Home/` | 21 | No |
| `Aura/Social/` | 18 | Partly (`SocialCore`) |
| `Assemblies/` | 14 | No (composition — correctly app-owned) |
| `Aura/WalletConnection/` | 12 | Partly (`WalletConnectorKit`) |
| `Aura/Search/` | 12 | **No** |
| `MusicApp/AuraPlay/` | 17 | Partly (`MusicFeature`) |
| `Aura/` root (router, shell, tabs, ERC-20 views) | 27 | Partly (`AuralisShellCore`) |
| `Helpers/`, `DataModels/`, `Networking/`, `Gas/` | 14 | No |

---

## Target Shape

### Why not exactly 8 packages

The 8-component model is the right **domain** decomposition. It is not directly expressible as 8 SPM
packages, for three concrete reasons found in the current graph:

1. **`AuraUI` cannot live in App Shell.** `MissionControlFeature`, `MusicFeature`, `NFTLibraryFeature`,
   and `AccountsFeature` all import it. App Shell sits *above* Mission Control. Putting the design
   system in App Shell creates a cycle.
2. **`CapabilitiesCore` cannot live in Policy + Capabilities.** `RuntimeCore` depends on it, and
   `AutopilotCore` (policy) depends on `RuntimeCore`. SPM forbids cyclic *package* dependencies even
   when the individual targets are acyclic, so the capability **vocabulary** must sit below both.
3. **The AuraPlay engines have zero kernel coupling.** `AuraPlayMediaCore` has no local dependencies at
   all. Folding them into a domain package would drag AVFoundation-weight code into the Auralis graph
   for no boundary benefit.

So the target is **8 domain packages + 4 non-domain packages = 12 Auralis-owned packages** (down
from 41 owned), plus unchanged `CodeScanner`. The physical workspace therefore ends with 13 local
package roots before ordinary URL-based third-party dependencies.
Stating that plainly is better than forcing a "8" headline that the compiler will reject.

### Tier 0 — Non-domain foundation (4 packages)

| Package | Targets | Absorbs |
|---|---|---|
| `AuralisFoundation` | `AuralisFoundation` initially; split internal targets only when a real consumer boundary requires it | The dependency-clean portions of `AuralisPrimaryModels`, plus `CapabilitiesCore`, `SwiftDataAdapters`, `UserDefaultsAdapters` |
| `AuraUI` | `AuraUI` | unchanged (design system + `A11yID` registry) |
| `AuraPlayEngines` | `AuraPlayMediaCore`, `AuraPlayAudioEngine`, `AuraPlayVideoEngine` | those three packages |
| `AuralisTestSupport` | `AuralisTestSupport` | unchanged |

`CodeScanner` stays vendored and untouched.

### Tier 1..8 — The domain packages

Listed in dependency order, low → high. **A package may only depend on packages above it in this list.**

#### 3. `AuralisRuntime`

The kernel. Owns doing work.

| Target | Absorbs |
|---|---|
| `RuntimeCore` | Existing action boundary, tool registry, hooks, event bus, context bundle contract, worklog, deterministic checks, actor attribution and generated-UI request schemas |
| `IntentCore` | New intent contract and authorization provenance; no inference-to-commitment shortcut |
| `CommitmentCore` | New durable commitment contract, dependencies, lifecycle, cancellation, delegation, escalation and success criteria |
| `RuntimeState` | Existing `AgentSession`, execution updates, worklogs, retries, pause/cancellation and runtime-state storage contracts |
| `OutcomeVerification` | Existing `OutcomeSpec`, `SuccessCriterion` and evaluation seams, extended to assess commitment fulfillment from evidence |
| `InferenceCore` | Existing `ModelRouting`, `ModelInferring`, route registry, inference telemetry and provider-neutral request/result contracts |
| `Planner` | **Merged 2026-10-24.** The unchanged `PlannerCore` module and its independent test target now live inside the `RuntimeCore` package root. |
| `Playbooks` | **Merged 2026-10-24.** The unchanged `PlaybookCore` module and its independent test target now live inside the `RuntimeCore` package root. Its portable output declaration is runtime-owned as `ArtifactOutputType`; `ArtifactCore.ArtifactType` remains a source-compatible alias in the receipts domain. |
| `Scheduling` | **Merged 2026-10-24.** `SchedulingCore` and its 51-test target now live inside the `RuntimeCore` package root. Scheduling publishes `RoutineArtifactDraft` and `RoutineArtifactPersisting`; RuntimeKit adapts those requests to the receipts-owned `ArtifactStore`, preventing a RuntimeCore → ReceiptsCore cycle. |
| `Performance` | **Merged 2026-10-24.** The unchanged `PerformanceCore` module and its 28-test target now live inside the `RuntimeCore` package root. |
| `Eval` | **Merged 2026-10-24.** The unchanged `EvalCore` module and its 49-test target now live inside the `RuntimeCore` package root. |
| `OperatorRegistry` | Canonical `OperatorManifest`, registry, lifecycle/status and compatibility vocabulary; evolves existing `OperatorSpec`, `ToolDefinition` and registry contracts |
| `InteropContracts` | Transport-neutral peer discovery/messaging/delegation-exchange contracts extracted from Social only when proven reusable |
| `RuntimeStorage` | **Merged 2026-10-26.** Runtime contracts remain in `RuntimeCore`; the unchanged concrete `OperatorRuntimeStorage` SwiftData module and its 56-test target live inside the `RuntimeKit` AppShell package, where Runtime and Receipts can be composed without a package cycle. |

RuntimeCore depends on `AuralisFoundation` only and must stay bare-`swift test`-able. Concrete runtime
persistence is composed in AppShell because it also depends on receipts-owned artifact storage. The
pure runtime targets must never import ENS, secp256k1, web3.swift, SwiftUI, concrete model providers,
concrete operators, UI renderers, or persistence adapters. Provider-specific inference implementations
belong outside `InferenceCore` and are injected through `ModelInferring`.

#### 6. `AuralisReceipts`

Proof and outputs.

| Target | Absorbs |
|---|---|
| `ReceiptsCore` | `ReceiptsCore` |
| `ReceiptStorage` | **Merged 2026-10-24.** The unchanged `ReceiptStorage` module and its integrity, compatibility, concurrency, reset, and tamper-evidence tests now live inside the `ReceiptsCore` package root. |
| `ArtifactCore` | **Merged 2026-10-24.** The unchanged `ArtifactCore` module and its independent tests now live inside the `ReceiptsCore` package root. |
| `ArtifactStorage` | **Merged 2026-10-24.** The unchanged SwiftData storage module and rollback/compatibility tests now live inside the `ReceiptsCore` package root. |
| `ReceiptsUI` | app `Receipts/*` timeline + detail + payload views (21 files) |

Depends on: Foundation, `AuralisRuntime`, `AuraUI`.

> Placement note: the user model puts the receipts *browser* in Mission Control. Keeping the receipt
> and artifact **views** next to their schema (as a separate `ReceiptsUI` target) lets Mission Control
> compose them without owning payload rendering. Mission Control still owns the surface.

#### 4. `AuralisContext`

What Auralis knows. **This is a net-new package** — today it is 16 loose files at app root.

| Target | Absorbs |
|---|---|
| `ContextCore` | `Context{Field,Scope,Source,Snapshot,Provenance,Freshness,SchemaVersion,RefreshState}`, `ContextModulePointer(s)`, `ContextModulePriority`, `ContextBalancesSummary`, `ContextLibraryPointers`, `ContextService` |
| `MemoryCore` | New durable memory values and protocols: provenance, sensitivity, retention, correction, deletion and portability |
| `MemoryStorage` | Durable memory adapter contracts and implementations; must not turn context capture into implicit retention |
| `MemoryRetrieval` | Task-scoped retrieval that contributes governed, provenance-bearing fields to context assembly |
| `ContextLive` | `LiveContextSource`, app-side live source adapters |

Depends on: Foundation, `AuralisRuntime` (`ContextBundle` lives in `RuntimeCore`).

#### 5. `AuralisPolicy`

The trust core.

| Target | Absorbs |
|---|---|
| `PolicyCore` | `PolicyCore` (modes, scopes, leases, revocation, blast radius) |
| `Autopilot` | **Merged 2026-10-24.** The unchanged `AutopilotCore` module and its 35-test target now live inside the `PolicyCore` package root. It hosts `DomainJudge` because the judge is a policy decision, not a runtime one. |

Depends on: Foundation and `AuralisRuntime`. Receipt persistence is performed by the governed host,
not imported by the policy decision targets.

#### 7. `AuralisCrypto`

Ethereum-specific capability, including accounts (an Auralis account *is* a wallet address).

| Target | Absorbs |
|---|---|
| `Accounts` | `AccountsCore` |
| `AccountStorage` | **Merged 2026-10-24.** The unchanged `AccountStorage` module and its 10-test target now live inside the `AccountsCore` package root, preserving the coordinator and its consumer-owned transaction participants. |
| `AccountsUI` | **Merged 2026-10-24.** The unchanged `AccountsFeature` product and its 18-test target now live inside the `AccountsCore` package root. |
| `Providers` | **Merged 2026-10-25.** `ProviderKit` and `ChainProviders` now live as distinct products/targets inside the `AccountsCore` crypto package root. |
| `ENS` | **Merged 2026-10-25.** The unchanged `ENS` product and its 8-test target now live inside `AccountsCore`; its web3 dependency remains isolated to that target. |
| `Explorer` | **Merged 2026-10-25.** The unchanged `ExplorerAdapter` product and its 17-test target now live inside `AccountsCore`. |
| `TokenStorage` | **Merged 2026-10-24.** The unchanged `TokenStorage` module and its 10-test target now live inside the `AccountsCore` package root; app `DataModels/{Chain,TokenHolding}.swift` and `Gas/` remain later consolidation work. |
| `NFT*` (5) | **Merged 2026-10-25.** `NFTKit`, `NFTDomain`, `NFTProviderAdapters`, `NFTPersistence`, and `NFTPresentation` now live inside `AccountsCore`, eliminating the former provider/NFT cycle as one atomic move. |
| `WalletConnect*` (7) | **Merged 2026-10-25.** `WalletConnectorKit` and its six independently linked adapter targets now live inside the `AccountsCore` crypto package root, with 180 tests and vendor SDK dependencies retained on adapter targets only. |
| `WalletActions` | app `Aura/WalletConnection/*` (12 files), `Networking/*`, `Aura/ERC20*` |

Depends on: Foundation, `AuralisRuntime`, `AuralisReceipts`, `AuralisPolicy`, `AuraUI`.

This is the largest package by far. It stays one package because the crypto trust surface should have
one boundary, but the internal targets are non-negotiable — `ENS` and `WalletConnect*` carry the heavy
third-party graph and must not be reachable from `Accounts` or `NFTDomain`.

#### 8. `AuralisOperators`

Extension. Capability consumers, never authority holders.

| Target | Absorbs |
|---|---|
| `OperatorCore` | **Merged 2026-10-25.** The unchanged policy/provenance support product and its 38-test target now live inside the `OperatorsFeature` package root. |
| `OperatorTools` | `OperatorsFeature` concrete tools, executors and the current catalog after its manifest vocabulary moves to Runtime |
| `ModelProviderAdapters` | Concrete provider clients implementing Runtime's provider-neutral `ModelInferring` contract; independent of individual operators |
| `InteropAdapters` | Future transport-specific peer discovery/messaging/delegation-exchange adapters implementing Runtime contracts |
| `MusicOperator` | **Merged 2026-10-25.** The unchanged `MusicFeature` domain, discovery, persistence, presentation, receipt integration, and 136-test target now live inside the `OperatorsFeature` package root; app-owned live adapters remain in `MusicApp/AuraPlay/*`. |
| `NFTLibraryOperator` | **Merged 2026-10-25.** The unchanged `NFTLibraryFeature` browsing UI, routing/presentation contracts, and 12-test target now live inside the `OperatorsFeature` package root. |
| `SocialOperator` | app `Aura/Social/*` (18 files) |

Depends on: Foundation, `AuralisRuntime`, `AuralisReceipts`, `AuralisPolicy`, `AuralisCrypto`,
`AuraPlayEngines`, `AuraUI`.

#### 2. `MissionControl`

The main app experience.

| Target | Absorbs |
|---|---|
| `MissionControl` | `MissionControlFeature` |
| `TrustedUI` | **Merged 2026-10-25.** The unchanged `TrustedUIKit` renderer, approval/intervention surfaces, and 65-test target now live inside the `MissionControlFeature` package root; presentation-independent schemas stay in `RuntimeCore`, and the renderer remains a distinct reusable product. |

Depends on: Foundation, `AuralisRuntime`, `AuralisReceipts`, `AuralisContext`, `AuralisPolicy`,
`AuralisCrypto`, and `AuraUI`. It does not depend on concrete `AuralisOperators` targets.

#### 1. `AuralisAppShell`

The container.

| Target | Absorbs |
|---|---|
| `ShellCore` | **Merged 2026-10-25.** The unchanged `AuralisShellCore` state machine, routing contracts, collaborator seams, and 26-test target now live inside the `RuntimeKit` AppShell package root. |
| `ShellUI` | app `Aura/{MainAuraView,MainAuraShell,MainTab*,AppRouter,AppRouteError,GlobalChromeView,ShellStatusView,ProfileDetailView,Settings/}`, `Aura/Home/`, `Aura/Newsfeed/`, `Aura/Primitives/` |
| `Search` | app `Aura/Search/*` (12 files) |
| `RuntimeHost` | `RuntimeKit` — process-wide singletons, receipt sink, the one place the kernel is wired to storage + policy |

Depends on: everything.

## Source-Backed Target And Model Ownership Matrix

The 2026-10-22 inventory found that `AuralisPrimaryModels` is not one domain. It currently contains
foundation identity/ownership values, Ethereum/account values, NFT values, music values, search
history, receipt wire types and a shared SwiftData schema. Moving it wholesale into Foundation would
violate domain ownership and make every low-level consumer see unrelated product models.

| Existing source/type family | Evidence in current source | Final owner | Boundary treatment |
|---|---|---|---|
| `PrincipalID`, `OwnershipDescriptor` | **Moved 2026-10-23.** Dependency-free Foundation-only values with their tests and architecture guards | `AuralisFoundation` | Keep opaque and value-only. Never infer authority or actor kind from `PrincipalID.rawValue`; ownership grants no capability. A single internal target avoids a needless public import pair while only these two tightly coupled values live there. |
| `CapabilityID`, descriptors, categories, use context | `CapabilitiesCore` has no local dependencies | `AuralisFoundation.Capabilities` | Stable vocabulary only. Policy decisions and leases do not move into Foundation. |
| Generic `JSONValue` | **Moved 2026-10-23.** Provider, NFT, music and app metadata consumers prove it is transport-neutral; a duplicate private MusicFeature implementation was retired | `AuralisFoundation` | Integer and double decoding remain distinct and are pinned by Foundation tests. Receipt-specific `ReceiptJSONValue` remains with Receipts. |
| `ReceiptJSONValue`, `ReceiptPayload`, `ReceiptMode` | **Moved 2026-10-23** to `ReceiptsCore/Models/ReceiptWireValues.swift`; compatibility tests pin JSON shapes and mode raw values | `AuralisReceipts.ReceiptsCore` | Preserve persisted wire values and compatibility. No aliases remain in PrimaryModels. |
| `ReceiptActor`, `ReceiptActorDetail`, `ReceiptAuthorityDetail` | **Moved 2026-10-23.** `ReceiptsCore/Models/ReceiptActorTypes.swift` owns the persisted forms; its adjacent bridge converts to/from `RuntimeCore.ActorRef` and `AuthorityRef`. `PolicyActionGating` accepts canonical `ActorRef`. | `AuralisReceipts.ReceiptsCore` | Runtime has no receipt dependency. Receipts depends inward on Runtime and performs tolerant reconstruction through `ActorRef.init(persistedKind:…)`. Architecture tests reject duplicate models and a bridge returning to RuntimeCore. |
| `ActorRef`, `AuthorityRef`, attribution, `AgentSession` | Existing RuntimeCore actor/session sources | `AuralisRuntime.RuntimeCore` / `RuntimeState` | Actor attribution is runtime event identity, not a replacement for `PrincipalID`. |
| `ModelRoute`, `ModelRouting`, `ModelInferring`, `ModelProviderRegistry`, telemetry | Existing RuntimeCore model sources and app `ModelProviderComposition` | `AuralisRuntime.InferenceCore`; composition in `AuralisAppShell.RuntimeHost` | Concrete providers implement the protocol outside Runtime. Local fallback never receives remote-provider telemetry. |
| `RuntimeEventBus`, event history/checkpoints, `WorkflowEvent` | Existing reliable/live RuntimeCore event contracts | `AuralisRuntime.RuntimeEvents` | Preserve bounded live UI streams and named lossless audit/performance streams. Transport adapters stay outside. |
| `OutcomeSpec`, `SuccessCriterion`, Eval criteria | Existing RuntimeCore/EvalCore types | `AuralisRuntime.OutcomeVerification` and `Eval` | Extend/reuse for commitment verification; do not equate tool success with fulfillment. |
| `PlanningGoal`, `Plan`, `PlanStep`, deliberation/templates | Existing PlannerCore | `AuralisRuntime.Planner` | Plans describe how and carry no authority. Intent and commitment references should be typed IDs/contracts. |
| No durable commitment entity | Executive Function document explicitly calls it a candidate primitive | `AuralisRuntime.CommitmentCore` | New contract required; connect intent, criteria, dependencies, authorization and evidence without embedding live execution state. |
| Context bundle/governance contracts | Existing RuntimeCore context contracts | `AuralisRuntime.RuntimeCore` | Runtime owns the minimum execution-facing contract. AuralisContext supplies governed bundles. |
| App `Context*`, `ContextService`, `LiveContextSource` | 16 app-owned context files | `AuralisContext.ContextCore` / `ContextLive` | Extract current snapshot/freshness/provenance behavior; use protocols for live sources. |
| No durable memory subsystem; only context preferences and session memory touches | No production `MemoryCore`/store; `AgentSessionMemoryTouch` is telemetry | `AuralisContext.MemoryCore`, `MemoryStorage`, `MemoryRetrieval` | New domain required. Context may read memory through retrieval protocols but cannot silently persist context. |
| `ReceiptRecord`, integrity/export contracts, `ReceiptStore`, stored receipts | Existing ReceiptsCore/ReceiptStorage | `AuralisReceipts.ReceiptsCore` / `ReceiptStorage` | Keep versioned integrity history and stated causality. Storage implements core protocols. |
| `Artifact`, `ArtifactDraft`, `ArtifactStore`, schemas | Existing ArtifactCore/ArtifactStorage | `AuralisReceipts.ArtifactCore` / `ArtifactStorage` | Artifact and receipt references remain explicit and non-interchangeable. |
| `EthereumAddress`, `Chain`, `EOAccountSource`, `AccountSummary` | Currently in PrimaryModels; consumed by Accounts/Provider/ENS | `AuralisCrypto.Accounts` / `Providers` | Crypto domain values leave Foundation. Persistence models live in adapter targets. |
| `AccountSummary` | **Moved 2026-10-23.** AccountsFeature and app home/profile surfaces are the real consumers | `AuralisCrypto.Accounts` (current `AccountsCore`) | Portable account value; no SwiftData dependency. The now-empty speculative `PortableDomainValues.swift` was removed. |
| `TokenHoldingsMetadataFreshnessPolicy` | **Moved 2026-10-23.** Only TokenStorage production code and token presentation tests consumed the twelve-hour policy | `AuralisCrypto.TokenStorage` (current `TokenStorage`) | Keep token refresh policy beside the persisted token model; it no longer lives in the mixed primary-model module. Three owner tests pin the before/at/future timestamp boundaries. |
| Account-scoped token lifecycle snapshot | **Moved 2026-10-23.** `TokenHoldingAccountSnapshot` and its capture/delete/restore participant now live with `TokenHolding` in TokenStorage | `AuralisCrypto.TokenStorage` | Conforms to Foundation's generic `ScopedPersistenceParticipant`; AccountStorage coordinates the shared transaction but no longer knows token fields. |
| `PrimaryStoreCopy` | **Moved 2026-10-23.** Only `AuralisApp` consumed this local-store recovery presentation text | `AuralisAppShell` composition (currently app target) | App-launch copy is not a portable domain model. It remains a small value beside the composition root until ShellUI extraction. |
| SwiftData `NFT`, `Tag` | PrimaryModels plus NFTKit domain/persistence consumers. **Inventory update 2026-10-23:** unused speculative `NFTIdentity` and `NFTMetadataSnapshot` values were deleted rather than migrated. | `AuralisCrypto.NFTDomain` / `NFTPersistence` | `Tag` follows NFT persistence because its only production relationship is `NFT.tags`. Introduce a value contract only when an actual consumer requires it. |
| Account-scoped NFT lifecycle snapshot and cleanup | **Moved 2026-10-23.** `NFTAccountSnapshot`, participant, and orphan contract/collection/tag pruning now live in NFTPersistence; duplicate AccountStorage cleanup was removed | `AuralisCrypto.NFTPersistence` | AccountStorage coordinates only. NFTPersistence owns NFT reconstruction and cleanup rules through `ScopedPersistenceParticipant`. |
| Token persistence | PrimaryModels/TokenStorage. **Inventory update 2026-10-23:** unused `TokenHoldingDescriptor` was deleted rather than migrated. | `AuralisCrypto.TokenDomain` / `TokenStorage` | Provider responses map to domain values at adapter boundaries; do not predeclare an unused portable shape. |
| `MusicLibraryItemDescriptor`, `MusicLibraryAvailability`, `MusicLibraryItem` | **Moved 2026-10-24.** The domain values and SwiftData model now live with their only behavior owner in MusicFeature; the unused `PlaylistDescriptor` remains deleted. | `AuralisOperators.MusicDomain` / `MusicPersistence` (current `MusicFeature`) | `MusicLibraryAccountPersistenceParticipant` owns account-scoped capture/delete/restore beside the model. AccountStorage receives it through a type-erased consumer-owned participant seam so Crypto does not depend on Operators. Playback-neutral media/session types remain in `AuraPlayEngines.AuraPlayMediaCore`. |
| `NFT.musicURL` and remote audio URL normalization | **Moved 2026-10-23.** Only music indexing/playback consumes the property and sanitizer | `AuralisOperators.MusicOperator` (current `MusicFeature`) | Playback URL policy no longer lives on the shared persisted NFT model. HTTP upgrade, HTTPS validation, and IPFS gateway normalization remain together. |
| `SearchHistoryRecord` | **Moved 2026-10-24.** The model, snapshot, and lifecycle participant now live beside Search UI/store in the app-owned Search domain; the unused `SearchHistoryValue` remains deleted. | `AuralisAppShell.Search` / `SearchPersistence` (currently app target) | App composition injects the Search participant through AccountStorage's type-erased seam. Account cleanup preserves one rollback/undo transaction: token, music, search, and NFT participants capture/delete/restore only through the coordinator-supplied `ModelContext` and never save independently. Schema-identity, complete round-trip, scope isolation, forced rollback, removal, overwrite, and undo tests passed. |
| `OperatorSpec`, `OperatorCatalog`, `ToolDefinition` | Existing OperatorsFeature catalog and Runtime tool schema | Manifest/registry contract in `AuralisRuntime.OperatorRegistry`; concrete catalog in `AuralisOperators.OperatorTools` | Evolve rather than duplicate. Static manifest declares support/requests; live permissions, context, progress and commitments remain runtime state. |
| `TrustedUIRequest` and TrustedUIKit views | Schema already in RuntimeCore; renderer in TrustedUIKit | `AuralisRuntime.RuntimeCore` and `MissionControl.TrustedUI` | Schemas remain presentation-independent; policy gates actions; AuraUI supplies design primitives. |
| Capability leases, policy evidence, autopilot authorizers | RuntimeCore, PolicyCore, AutopilotCore | Leases/reference contracts in Runtime where already required; authority evaluation in `AuralisPolicy` | Delegation records never grant more authority than the principal possesses; revocation is checked at execution. |

### Canonical `OperatorManifest` responsibility contract

The canonical type must be chosen only after reconciling `OperatorSpec`, `ToolDefinition`,
`OperatorCatalog` and any historical OperatorCore definitions. Its semantic contract is fixed now:

| Responsibility | Static manifest declaration |
|---|---|
| Identity and purpose | Stable operator ID, version, description, intended outcomes, principal scope |
| Context and memory | Required context, permitted memory access, data scopes, freshness requirements |
| Reasoning and plans | Planning capabilities, workflows, decision boundaries, alternatives |
| Capabilities and tools | Required capabilities, accepted inputs, output contracts, external effects |
| Authority and policy | Requested permissions, risk classification, confirmation boundaries, revocation behavior |
| Execution and commitments | Supported commitment types, lifecycle hooks, cancellation, retry and recovery behavior |
| Events and scheduling | Subscribed event categories, triggers, idempotency requirements |
| Artifacts and receipts | Artifact types, receipt requirements, evidence and provenance references |
| Outcomes and evaluation | Success criteria, verification requirements, failure and escalation semantics |
| Interface and lifecycle | UI representations, approval/intervention surfaces, lifecycle and compatibility requirements |

The manifest describes what an operator supports and requests; it grants no authority. AI, schedules
and persistent memory are optional requirements. Current permissions, executions, context and active
commitments are runtime state, never immutable manifest metadata.

## Target-Level Dependency Graph

Allowed Auralis-owned package dependencies are listed below. Internal targets must narrow these
further; a package-level edge is permission to define target edges, not permission for every target
to import every other target.

```text
AuralisFoundation        -> (none)
AuraUI                    -> AuralisFoundation only when shared value contracts require it
AuraPlayEngines           -> (none; MediaCore <- AudioEngine, VideoEngine internally)
AuralisTestSupport        -> AuralisFoundation only
AuralisRuntime            -> AuralisFoundation
AuralisReceipts           -> AuralisFoundation, AuralisRuntime, AuraUI (ReceiptsUI only)
AuralisContext            -> AuralisFoundation, AuralisRuntime
AuralisPolicy             -> AuralisFoundation, AuralisRuntime
AuralisCrypto             -> AuralisFoundation, AuralisRuntime, AuralisReceipts,
                             AuralisPolicy, AuraUI
AuralisOperators          -> AuralisFoundation, AuralisRuntime, AuralisReceipts,
                             AuralisContext, AuralisPolicy, AuralisCrypto,
                             AuraPlayEngines, AuraUI
MissionControl            -> AuralisFoundation, AuralisRuntime, AuralisReceipts,
                             AuralisContext, AuralisPolicy, AuralisCrypto, AuraUI
AuralisAppShell           -> all selected packages, including concrete AuralisOperators
```

Critical negative edges:

- Runtime does not import concrete providers, operators, policy implementations or UI renderers.
- Mission Control does not import concrete operator packs; it reads registry/lifecycle contracts.
- Policy does not import receipt persistence. The governed host records required evidence and fails
  closed before consequential execution when durable evidence is mandatory.
- Context does not import Memory storage implementations from its contract target, and context
  assembly never writes memory implicitly.
- Foundation contains no crypto, NFT, music, search, receipt or SwiftData domain model.
- Test support contains no receipt/storage dependency; domain-specific fixtures stay with owners.

### What stays in the app target

Only composition and app-lifecycle code:

- `AuralisApp.swift`, `AppContext.swift`, `AppServices.swift`, `AppLaunchConfiguration.swift`
- `Assemblies/*` (14 files) — this is the composition root and should stay
- `PrimaryStoreSchema.swift`, `PreviewModelContainers.swift`
- `LogoutCleanupService.swift`, `PrivacyResetService.swift`, `LocalDataClassification.swift`,
  `SwiftDataShellSupportCleanup.swift`
- `Helpers/*` that are genuinely app-scoped (`ExternalLinkPolicy`, `ExternalWalletAppProbe`);
  `String.swift`, `StringHelpers.swift`, `URL.swift`, `ModelContextDestructiveMutation.swift`
  move to `AuralisFoundation`

Target: **193 → ~25 files** in the app target.

---

## Required Refactors (blocking, not optional)

These are dependency-graph problems the consolidation surfaces. Each must be fixed *before* the merge
that would otherwise create a cycle.

### 1. `CapabilitiesCore` moves to `AuralisFoundation`

`RuntimeCore` → `CapabilitiesCore` and `AutopilotCore` → `PolicyCore` → `CapabilitiesCore`, while
`AutopilotCore` → `RuntimeCore`. As long as capabilities and policy share a package, `AuralisRuntime`
and `AuralisPolicy` are mutually dependent. Capability vocabulary (IDs, scopes, impact classes) is
value-only and belongs in the foundation tier. Policy *enforcement* stays in `AuralisPolicy`.

**Completed 2026-10-23:** the `CapabilitiesCore` product, target, and test target now live inside the
dependency-free `AuralisFoundation` package. Consumer imports and the public module name remain
unchanged; only their package identity/path changed. The retired package manifest is guarded against
returning. Validation passed for Foundation 24/24, RuntimeCore 240/240, PolicyCore 10/10,
MusicFeature 133/133, Xcode build-for-testing, and both package/import architecture guards.

**Completed later 2026-10-23:** the generic `SwiftDataAdapters` and `UserDefaultsAdapters` products,
targets, and test targets also moved into `AuralisFoundation`. Their module names and APIs did not
change. The UserDefaults test suite stopped importing higher-level `AuralisTestSupport`, removing a
reverse test edge. Validation passed for Foundation 34/34, AccountStorage 8/8, ArtifactStorage 26/26,
ReceiptStorage 207/207, TokenStorage 7/7, Xcode build-for-testing, and both architecture guards.

### 2. `MissionControlFeature` must stop importing `OperatorsFeature`

Today `MissionControlFeature` depends on `OperatorsFeature` (concrete tools). That inverts the stated
rule that packs are consumers, and it would make Mission Control depend on package 8. Fix:

- Mission Control depends on the `OperatorRegistry` target in `AuralisRuntime` (manifest, status,
  install/disable protocol).
- Concrete packs register into that registry.
- `AuralisAppShell` composes the concrete packs.

This is the single most important refactor in the plan — without it, packs and the console are welded
together and Prixio cannot be added without touching Mission Control.

### 3. `RuntimeKit` moves out of the kernel into App Shell

`RuntimeKit` depends on `PolicyCore`, `OperatorsFeature`, `ReceiptStorage`, `SocialCore`, and 11 others.
It is the app host, not the kernel — ADR-008 already places it at layer 7. It becomes the `RuntimeHost`
target inside `AuralisAppShell`. `AuralisRuntime` must not contain it.

### 4. `MissionControlFeature` must stop importing `SocialCore` directly

Social behavior becomes an AuralisOperators pack. Move only transport-neutral peer/discovery/message
contracts into `AuralisRuntime.InteropContracts`; Mission Control reads social/operator status through
the registry rather than importing the pack.

### 5. Split `AuralisPrimaryModels` by domain before Foundation consolidation

The source inventory found crypto/account, NFT, token, music, search, receipt and foundation values in
the same dependency-free module. Move them to the owners in the matrix above while preserving
explicit conversion boundaries and persisted compatibility. `PrincipalID` and
`OwnershipDescriptor` remain separate from `ActorRef`, authority and policy.

**Started 2026-10-23:** `PrincipalID`, `OwnershipDescriptor`, and their complete test suite moved to
the new zero-dependency `AuralisFoundation` root. `ReceiptsCore` and `ReceiptStorage` now declare the
dependency explicitly. No forwarding aliases remain in `AuralisPrimaryModels`, so ownership is
singular and enforced by compilation.

**Continued 2026-10-23:** `ReceiptJSONValue`, `ReceiptPayload`, and `ReceiptMode` moved to
`ReceiptsCore` with explicit imports and wire-compatibility tests. `PolicyActionGating` now accepts
the canonical runtime `ActorRef`, removing receipt-shaped attribution from the authorization API and
from Autopilot's call path. The actor and authority receipt types remain temporarily in PrimaryModels
only while the bidirectional Runtime receipt bridge is relocated outward. Moving those declarations
before relocating that bridge would violate the final dependency graph.

**Completed later 2026-10-23:** the bridge and `ReceiptActor`, `ReceiptActorDetail`, and
`ReceiptAuthorityDetail` moved into `ReceiptsCore`. RuntimeCore now exposes only a domain-neutral,
tolerant `ActorRef.init(persistedKind:…)` reconstruction seam for durable adapters; it contains no
receipt types or conversions. Mixed bridge tests moved with the bridge, while pure Runtime tests stay
in RuntimeCore.

### 6. Remove the reverse test-support dependency

`AuralisTestSupport` currently depends on `ReceiptStorage`, while lower packages depend on
`AuralisTestSupport`. The final test-support package may depend only on Foundation. Receipt fixtures,
SwiftData containers and storage doubles that know receipt schemas stay in AuralisReceipts tests.

**Completed 2026-10-22:** `StoredReceiptFixture` moved to the app integration test target, the
`ReceiptStorage` package/import edge was removed from AuralisTestSupport, and
`ArchitectureBoundaryTests.sharedTestSupportStaysDependencyClean` now guards the boundary. The
remaining PrimaryModels/Persistence fixture split belongs to Phase 1 domain-model ownership work.

### 7. Decouple policy decisions from receipt persistence

`PolicyCore` currently imports `ReceiptsCore`, accepts `ReceiptStore` and constructs receipt drafts.
Policy should return a typed decision/evidence event. The governed host converts that event into a
receipt and must record required evidence successfully before consequential execution. This removes
the Receipts/Policy coupling without weakening fail-closed behavior.

### 8. Move Ethereum checks out of generic Runtime targets

`RuntimeCore` currently imports primary models for `ChainScopeReference` and Ethereum aliases. Keep
generic deterministic-check protocols/results in Runtime; move chain parsing, known-chain lookup and
crypto checks to AuralisCrypto and register them through the existing check registry.

### 9. Inventory before adding intent, commitment, memory or manifest types

Reuse `PlanningGoal`, `Plan`, `AgentSession`, `WorkflowEvent`, `OutcomeSpec`, context contracts,
`OperatorSpec` and `ToolDefinition`. New types are limited to genuinely absent semantics—most notably
durable Commitment and Memory—and must not create a second execution, event, outcome or registry
framework.

---

## Migration Order

> The order in the original sketch (`AppShell` first) is the **Prixio rebase** order — the sequence in
> which a second product adopts finished layers. It is not the consolidation order. Repackaging must go
> **bottom-up**, or every intermediate state has a broken graph.

| Phase | Work | Local-root checkpoint (includes CodeScanner) |
|---|---|---|
| 0 | Fix the nine required refactors above, freeze the ownership matrix, and add import-boundary tests. No package merges. | 42 → 42 |
| 1 | Split `AuralisPrimaryModels` by owner; create narrow `AuralisFoundation`; merge capability/mechanics adapters only after reverse dependencies are removed; **`AuraPlayEngines`, `CapabilitiesCore`, `SwiftDataAdapters`, and `UserDefaultsAdapters` roots merged 2026-10-23** | Completed with 38 local roots (37 owned + CodeScanner), preserving the former package modules and independent test targets |
| 2 | `AuralisRuntime` (merge runtime contracts/companions; route concrete Social and host sources to their final owners). **PlannerCore, PlaybookCore, PerformanceCore, and EvalCore roots merged into RuntimeCore 2026-10-24.** | Current: 34 local roots (33 owned + CodeScanner); four Runtime companion roots eliminated while preserving their modules and test targets |
| 3 | `AuralisReceipts` (merge 4 packages + move 21 app files). **ArtifactCore, ArtifactStorage, and ReceiptStorage roots merged into ReceiptsCore 2026-10-24.** | Current: 31 local roots (30 owned + CodeScanner); three receipt/artifact roots eliminated while preserving modules and test targets |
| 4 | `AuralisContext` (extract 16 app context files and add Memory contracts/storage/retrieval without duplicating Runtime context contracts) | Net-new owned package; record actual delta |
| 5 | `AuralisPolicy` (merge 2 packages after receipt decoupling) | Record actual delta |
| 6 | `AuralisCrypto` (merge crypto packages + move app crypto files) | Record actual delta |
| 7 | `AuralisOperators` (merge concrete operator/music/NFT-library/Social sources + move app operator files) | Record actual delta |
| 8 | `MissionControl` and `AuralisAppShell` final merges and app-source extraction | Must finish at 13 local roots: 12 owned + CodeScanner |

Rationale for the two deviations from a pure bottom-up sweep:

- **Context (Phase 4) comes before Policy** even though it is "layer 4", because it is net-new
  extraction from the app target and unblocks nothing else. Doing it early keeps the app target
  shrinking steadily instead of all at the end.
- **Crypto (Phase 6) is the riskiest phase.** It carries the entire third-party graph (reown, web3.swift,
  secp256k1, Privy, Dynamic, Coinbase). Do it after the kernel is stable so a resolution failure has a
  known-good rollback point.

Each phase is one PR per package merge, minimum. Phase 6 should be at least three PRs
(accounts+storage, providers+ENS+explorer, wallets+NFT).

---

## Acceptance Criteria Per Phase

A phase closes only when all of these hold:

- [ ] `DEVELOPER_DIR=<Xcode-beta> swift test --package-path <NewPackage>` passes in isolation.
- [ ] Every target that was independently `swift test`-able before is still independently testable —
      merged packages must not merge test targets.
- [ ] No target in the new package imports a package below it in the layer list.
- [ ] `Auralis` scheme builds via `BuildProject`.
- [ ] `Auralis-Full` test plan passes (not `Auralis-Fast` — see the memory note; Fast is an iteration
      tool, not release evidence).
- [ ] Architecture boundary tests in `AuralisTests` are updated to assert the *new* import graph.
- [ ] Snapshot baselines unchanged, or re-recorded with an explicit note in the PR.
- [ ] The app target file count went **down**.
- [ ] `AGENTS.md` "High-Value Docs" ownership lines updated for the merged packages.

---

## Enforcement

The mechanism from ADR-008 carries forward unchanged and is the reason the merge is safe:

1. **Isolated `swift test` per package** is the boundary test. A package that cannot build alone has a
   boundary violation. This is what keeps a 12-package graph from degenerating into a monolith.
2. **Internal targets, not folders.** Every layer that exists today as a package must exist tomorrow as
   a *target* with its own dependency list. Merging packages into one target is the failure mode this
   plan is specifically trying to avoid.
3. **Architecture tests in the app target** assert the allowed import graph so drift fails CI.
4. **Only app-linked packages get an `XCLocalSwiftPackageReference`.** After consolidation the app
   should link `AuralisAppShell` and `MissionControl`; everything else resolves transitively.

Precedent that this works: `NFTKit` (5 targets), `AuralisPrimaryModels` (2 targets), and
`WalletConnectorKit` (7 targets) are already multi-target packages with clean internal layering.

---

## Interaction With TEST-015

TEST-015 (moving behavioral coverage from `AuralisTests` into owning packages) is **a prerequisite for
the phases it overlaps**, not a parallel effort. Moving a test into `NFTKit` and then merging `NFTKit`
into `AuralisCrypto` is two moves for the same assertion.

Recommended sequencing:

- TEST-015 Slices 1–2 (NFTKit, MusicFeature) → do them **as part of** Phases 6 and 7, targeting the
  final package directly.
- TEST-015 Slice 3 (ProviderKit split) → do it **before** Phase 6; it is a split, and splitting is
  easier before merging.
- TEST-015 Slice 4 (AuraUI, PrimaryModels, AccountsCore) → do it **as part of** Phases 1 and 6.

The TEST-015 acceptance checklist should be re-scoped to the new package names when Phase 1 lands.

---

## Rebasing Prixio

Once the layers are consolidated, Prixio is **not a second app architecture**. It is a set of operator
packs plus artifacts plus workflows inside `AuralisOperators`.

Adopt in the order originally sketched — that order is correct for a *consumer* of finished layers:

| Step | Layer | What Prixio gets |
|---|---|---|
| 1 | App Shell | tab host, routing, account switcher, theming |
| 2 | Receipts + Artifacts | `PriceCaptureArtifact`, `PriceHistoryArtifact`, receipt trail |
| 3 | Context + Memory | `StoreContext`, price history, user preferences, freshness |
| 4 | Runtime | `GroceryListWorkflow`, `FinanceTrackingWorkflow`, scheduled price refresh |
| 5 | Mission Control | queued captures, approvals, pack status |
| 6 | Policy + Capabilities | spend limits, capability leases for commerce actions |
| 7 | Operator Packs | `PriceCaptureOperator`, `StorePriceTrackerOperator`, `MealPlannerOperator` |
| 8 | Crypto / Web3 | commerce/stablecoin rails, agent mandates |

The canonical Prixio flow maps onto the kernel with no new primitives:

```
take picture of price
  → PriceCapture artifact          (AuralisReceipts.ArtifactCore)
  → attach store/product context   (AuralisContext)
  → generate receipt               (AuralisReceipts.ReceiptsCore)
  → update price-history memory    (AuralisContext)
  → run workflow                   (AuralisRuntime)
  → show in Mission Control        (MissionControl)
  → later: commerce/crypto rails   (AuralisCrypto)
```

**Do not merge Prixio as `PrixioFeature`.** A feature package would re-create the exact pack/console
coupling that Required Refactor 2 removes. Merge it as operators, artifacts, and workflows.

---

## Risks

| Risk | Mitigation |
|---|---|
| A merged package becomes un-`swift test`-able because one target drags a heavy dependency | Targets keep independent dependency lists; CI runs isolated `swift test` per package every phase. The `AgentIdentityCore` removal is the precedent for what happens when this is ignored. |
| Phase 6 breaks SPM resolution across reown/web3.swift/secp256k1 | Split Phase 6 into three PRs; keep `Package.resolved` diffs reviewable; do it after the kernel is stable so rollback is cheap. |
| Stale `.swiftmodule` artifacts produce a phantom "cannot find type X" cascade | Known failure mode — delete `DerivedData/**/Build/Products/*.swiftmodule` for the renamed module and rebuild before investigating. |
| Snapshot baselines churn when view files move packages | Baselines are byte-compared PNGs; moving a file should not change output. If they churn, that is a real signal — investigate rather than re-record. |
| Consolidation is used as cover to widen access modifiers | Access widening requires an explicit justification line in the PR description. Prefer moving the type to the right target over making it `public`. |
| One giant PR | Hard cap: one package merge per PR; Phase 6 and 8 are multi-PR by mandate. |

---

## Placement Decisions And Deferred Questions

1. **Does the receipts browser UI belong to `AuralisReceipts` or `MissionControl`?**
   This plan puts the *rendering* in `AuralisReceipts.ReceiptsUI` and the *surface* in `MissionControl`.
   The alternative — all 21 files into Mission Control — is defensible and simpler, but couples payload
   rendering to the console. Recommendation: keep the split; revisit if `ReceiptsUI` never gets a second
   consumer.

2. **Social is an operator implementation, not Runtime core.**
   **Merged 2026-10-24.** The `SocialCore` module and its 185-test target now live inside the
   `OperatorsFeature` package root, preserving the module boundary while placing relay, persistence,
   and social behavior with the eventual `AuralisOperators` owner. `SocialCore` depends on
   `RuntimeCore` + `PlaybookCore` and is imported by both `RuntimeKit` and
   `MissionControlFeature`. Its shared peer/event contracts move to a narrow Runtime interoperability
   target only when transport-neutral; social models, persistence and relay behavior move to
   `AuralisOperators.SocialOperator`. Mission Control reads status through registry contracts.

3. **Where does Newsfeed go?**
   Four files, currently a shell tab. Parked in `AuralisAppShell.ShellUI`. It is a product surface and a
   plausible operator pack. Recommendation: leave in App Shell; promote only if it grows a workflow.

4. **`ENS` remains a separate target inside `AuralisCrypto`.**
   It carries `web3.swift` + `secp256k1`, so no core Crypto target may depend on it. It is not a 13th
   Auralis-owned package; third-party dependencies remain ordinary external packages.

---

## Summary

```
Before: 41 Auralis-owned packages + CodeScanner + 193 app-target Swift files (2026-10-22 inventory)
After:  12 Auralis-owned packages + CodeScanner + ~25 app-target files
Third-party URL dependencies are excluded from both counts.

Foundation ──→ Runtime ──→ {Receipts, Context, Policy}
                                │         │       │
                                └─────────┴───────┴──→ Crypto ──→ Operators
                                                      │             │
Foundation + Runtime + domain packages ───────────────┴──→ MissionControl
All selected packages, including concrete Operators ─────→ AppShell ──→ Auralis app

AuraUI is a presentation dependency of feature/UI targets.
AuraPlayEngines is consumed by media operator targets.
AuralisTestSupport is test-only and depends on Foundation alone.
```

The count matters less than the two properties it buys: **one obvious home for every new file**, and
**a graph where Prixio is additive rather than structural**.
