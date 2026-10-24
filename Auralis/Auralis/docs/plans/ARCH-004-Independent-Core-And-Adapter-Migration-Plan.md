# ARCH-004: Independent Core And Adapter Target Migration Plan

Status: Revised to support the approved 12-package structure
Date: 2026-10-22
Builds on: `ARCH-003-Domain-Package-Consolidation-Plan.md`
Related: `TEST-015-Package-Ownership-Migration-Proposal.md`

## Decision And Supersession

The earlier version of ARCH-004 required every core, adapter, engine and operator pack to retain an
independent repository, manifest and release lifecycle. That requirement conflicted with the approved
goal of reducing 41 Auralis-owned packages to 12.

This revision supersedes that publication strategy. Independence is enforced primarily by **targets
inside the 12 packages**, explicit product surfaces, dependency direction, protocols, generic
algorithms, type erasure at heterogeneous boundaries, architecture tests and isolated target tests.

The final workspace has:

- 12 Auralis-owned packages;
- vendored `CodeScanner`, excluded from the 12-package count;
- ordinary third-party URL dependencies, also excluded;
- multiple narrowly dependent targets inside each owned package.

An internal target may later be published independently when a real external consumer requires it,
but speculative publication boundaries do not control this consolidation.

## Architecture Fit

This is Clean Architecture at package scale:

```text
App composition and lifecycle
    -> UI and concrete adapters
        -> use cases and orchestration
            -> domain values and consumer-owned protocols
```

Dependencies point inward. SwiftUI, SwiftData, vendor SDKs, transports and process-wide hosts are
implementation details. Domain targets own the values and contracts that give behavior meaning.

## Boundary Rules

1. **A model lives with the domain that gives it meaning.** Shared use alone does not make a model a
   Foundation primitive.
2. **Protocols are owned by their consumers.** A domain declares the storage, inference, context or
   execution behavior it needs; outward adapters implement it.
3. **Generics serve typed algorithms.** Use them for stores, resolvers, transformations, construction
   and small reusable algorithms. Do not make the entire runtime generic over every environment.
4. **Existentials or narrow type erasure serve long-lived heterogeneous systems.** Registries,
   process-wide hosts, SwiftUI injection and mixed provider/operator collections should not leak deep
   generic parameter graphs.
5. **Persistence types are adapters.** SwiftData models do not become universal domain values merely
   because several screens read them.
6. **DTOs and vendor types stop at adapter boundaries.** Convert them into domain-owned values before
   they enter use cases, policy or presentation.
7. **Capability never implies authority.** Operator manifests and tool definitions describe support
   and requested permissions; current delegation plus policy authorizes an execution.
8. **State categories remain distinct.** Intent, plan, commitment, runtime state, memory, context,
   artifact and receipt may reference one another through typed IDs, but are not aliases.
9. **Cancellation and failure cross async seams honestly.** `async` protocols preserve cancellation;
   adapters return typed failures rather than hiding provider or persistence errors.
10. **No accidental transitive imports.** Every target declares modules it imports directly.

## Sovereignty Invariants

- An inferred intent does not silently become an authorized commitment.
- A plan does not grant itself execution authority.
- Runtime success does not automatically fulfill a commitment.
- Context does not silently become durable memory.
- Artifacts and receipts are independently owned records.
- A receipt is evidence; outcome verification interprets evidence against success criteria.
- Revocation prevents further unauthorized execution regardless of memory or context.
- `PrincipalID`, runtime `ActorRef`, ownership, capability, policy and receipt attribution remain
  separate concepts. Ownership metadata grants no authority.

## Source Inventory Findings

The 2026-10-22 inventory establishes the starting facts below.

### Existing reusable contracts

Do not recreate these:

| Responsibility | Existing implementation |
|---|---|
| Model routing and inference | `RuntimeCore/Model/ModelRouting.swift`, `ModelProviderRegistry.swift`, app `ModelProviderComposition` |
| Live and reliable events | `RuntimeEventBus`, event history/checkpoint protocols, `WorkflowEvent` |
| Outcome specifications | `OutcomeSpec`, `SuccessCriterion`, EvalCore criteria/results |
| Runtime identity | `ActorRef`, `AttributionContext`, `AuthorityRef` |
| Principal and ownership vocabulary | `PrincipalID`, `OwnershipDescriptor` |
| Generated-UI request schema | `TrustedUIRequest` in RuntimeCore |
| Generated-UI renderer | TrustedUIKit components and models |
| Capability/authority primitives | Capability descriptors, leases, restrictions, policy evidence and decisions |
| Plans and workflows | PlannerCore plans/goals, PlaybookCore playbooks, SchedulingCore routines |
| Runtime state | `AgentSession`, execution updates, worklogs, pause/cancellation hooks |
| Receipts and integrity | Receipt contracts, store protocol, versioned integrity envelopes, export/verification |
| Artifacts | Artifact values, drafts, schemas and store protocol |

### Genuinely absent first-class domains

| Responsibility | Evidence-backed conclusion |
|---|---|
| Durable commitment | No production commitment entity was found. `PlanningGoal`, `Plan`, `AgentSession` and scheduling records cover adjacent but distinct semantics. Add by composing/referencing them, not renaming one. |
| Durable memory | No production memory domain/store was found. `ContextLocalPreferences` and `AgentSessionMemoryTouch` are not a portable, user-controlled memory system. |
| Explicit intent | Intent appears in feature-specific names such as transaction intent, but no provider-neutral intent contract captures source and authorization degree. Add only after reconciling current goal/request types. |
| Complete operator manifest | `OperatorSpec`, `ToolDefinition` and catalogs cover part of the contract. Evolve a canonical manifest after inventory; do not add a parallel registry. |

### Current dependency violations to remove

- `RuntimeCore` imports primary models and contains Ethereum `ChainScopeReference` aliases.
- `PolicyCore` imports receipt types, accepts a `ReceiptStore` and constructs receipt drafts.
- `MissionControlFeature` imports concrete `OperatorsFeature` and `SocialCore`.
- `RuntimeKit` is a high-level process host but is packaged beside reusable runtime code.
- `AuralisTestSupport` imports `ReceiptStorage`, creating a reverse test dependency.
- `AuralisPrimaryModels` mixes foundation, crypto, NFT, music, search, receipt and persistence owners.
- Current manifests rely on sibling path dependencies; consolidation must replace those edges with
  internal target dependencies rather than preserve package-level coupling accidentally.

## Final Placement Recommendations

ARCH-003 contains the complete model matrix. The placement decisions relevant to core/adapter
independence are:

### AuralisFoundation

Own only portable primitives, `PrincipalID`, ownership vocabulary, capability vocabulary and generic
persistence/defaults mechanics. It must not own Ethereum, NFT, music, search, receipt or SwiftData
domain models.

The dependency-free `CapabilitiesCore` module/product moved into this package on 2026-10-23 without
changing its API or collapsing its test target. Foundation passed 24/24 tests; representative
consumers RuntimeCore, PolicyCore and MusicFeature passed 240/240, 10/10 and 133/133 respectively;
Xcode build-for-testing and both package/import architecture guards also passed.

The generic `SwiftDataAdapters` and `UserDefaultsAdapters` targets/products followed on 2026-10-23.
Domain-specific stores remain outside Foundation. The consolidated Foundation suite passed 34/34;
all four SwiftData consumers passed 248/248 combined; build-for-testing and both architecture guards
passed after Xcode relinking.

Generic recursive `JSONValue` moved from PrimaryModels into the dependency-free Foundation target on
2026-10-23 after its provider, NFT, music, and app consumers proved it was transport-neutral. The
parallel private MusicFeature JSON enum was removed. Receipt wire JSON remains a separate
receipt-owned type. Foundation passed 23/23, PrimaryModels 10/10, NFTKit 52/52, ProviderKit 22/22,
MusicFeature 133/133, build-for-testing, and both architecture guards passed.

The next PrimaryModels inventory removed five unused speculative transfer values rather than moving
them: `NFTIdentity`, `NFTMetadataSnapshot`, `TokenHoldingDescriptor`, `PlaylistDescriptor`, and
`SearchHistoryValue` had no production or test consumers. `AccountSummary` remains because it is an
active account-domain boundary. Build-for-testing and the package-graph/ownership guard passed. The
same inventory confirms that AccountStorage's current cross-domain cleanup cannot be replaced by
ordinary callbacks: account, token, search, music, and NFT changes share one rollback-safe SwiftData
transaction and removal undo snapshot. Any future adapter split must preserve that transaction
boundary explicitly. That review also found two missing restoration paths in the existing snapshot:
deleted `MusicLibraryItem` rows and captured NFT attributes were not restored by undo. Both are now
restored and covered by the focused app integration test. The final seam should therefore be a
transaction coordinator plus domain-owned snapshot participants, not independent post-commit
cleanup services.

The first transaction-aware seam landed on 2026-10-23. `AccountScopedPersistenceParticipant` gives
token, music, search, and NFT persistence separate capture/delete/restore implementations while the
account coordinator retains the sole `ModelContext`, rollback-safe mutation, save, and undo
registration. This is deliberately an internal extraction seam first; participants move beside their
domain models only after their target dependencies are available. Build-for-testing and four focused
account/architecture checks passed. Deterministic failure injection then exposed that SwiftData typed
batch deletes did not return token and music rows on `ModelContext.rollback()`. Those participants now
fetch and delete individual models inside the shared transaction. The injected late failure and the
four existing regression checks all pass.

The generic contract then moved down to `SwiftDataAdapters` as `ScopedPersistenceParticipant`, with
no account or domain vocabulary. TokenStorage now owns its complete account-scope snapshot and
participant, and NFTPersistence owns the NFT snapshot, participant, and the single orphan-pruning
implementation for contracts, collections, and tags. AccountStorage retains orchestration but no
longer knows token or NFT snapshot fields. Build-for-testing and five rollback, undo, overwrite,
package-graph, and NFT-layer checks passed after the NFT extraction.

Music followed on 2026-10-24 without creating the forbidden Crypto → Operators edge.
`MusicLibraryItem`, its availability/descriptor values, snapshot, and account lifecycle participant
now live in MusicFeature. AccountStorage consumes a type-erased participant assembled by the app, while
retaining sole ownership of the `ModelContext`, rollback-safe transaction, save, and undo registration.
The move also removed the music-specific SwiftData fixture from `AuralisTestSupport`. MusicFeature
passed 136 tests, AccountStorage passed 10, PrimaryModels passed 10, eight focused app integration and
architecture tests passed, and Xcode build-for-testing succeeded.

Search followed through the same seam on 2026-10-24. `SearchHistoryRecord`, its complete snapshot,
and its account lifecycle participant now live together in the app-owned Search domain. AccountStorage
retains no Search fields or concrete Search type dependency; app composition injects the participant
beside Music. AccountStorage and PrimaryModels each passed 10 tests, eleven focused app architecture,
schema, scope, removal, overwrite, undo, and forced-rollback tests passed, and Xcode build-for-testing
succeeded.

### AuralisRuntime

Own provider-neutral execution and orchestration contracts:

- `RuntimeCore`, hooks, tools and checks;
- `IntentCore`;
- `CommitmentCore`;

The first physical Runtime consolidation landed on 2026-10-24: the unchanged `PlannerCore` source
module and `PlannerCoreTests` target moved under the `RuntimeCore` package root. Direct consumers now
resolve the `PlannerCore` product from that package, with no source import or public API changes.
RuntimeCore/Planner, Autopilot, RuntimeKit, and Mission Control package suites passed, the standalone
root is rejected by an architecture guard, and Xcode build-for-testing succeeded.

The second Runtime companion followed the same day: `PlaybookCore` and `PlaybookCoreTests` moved
under the `RuntimeCore` package root. A direct move initially exposed a real dependency-direction
problem: playbooks named `ArtifactType`, while `ArtifactCore` already depends on Runtime. Moving the
artifact module into Runtime would have violated its final AuralisReceipts owner. Instead, the six-case
portable declaration moved inward as `RuntimeCore.ArtifactOutputType`, and
`ArtifactCore.ArtifactType` became a source-compatible alias. Runtime therefore describes allowed
outputs without depending outward on receipts, while the artifact model and store stay in their
correct domain.

`PerformanceCore` then moved intact into the same package as an independent internal target. It
has no production dependencies, so the move required only product-address rewiring in its five
consumers. RuntimeCore passed 314 tests, those consumers passed 566 tests, the package-graph guard
passed, and Xcode build-for-testing succeeded.

`EvalCore` followed as another independent internal target once Performance was available inside
RuntimeCore. Its source and public module remained unchanged; three consumers now resolve the product
from RuntimeCore. The owner and consumer suites passed 829 tests, the package-graph guard passed, and
Xcode build-for-testing succeeded.
- runtime state and sessions;
- runtime events and reliable delivery contracts;
- planner, playbooks and scheduling;
- outcome verification, evaluation and performance;
- inference routing/request/result contracts;
- canonical operator manifest and registry contracts;
- transport-neutral interoperability contracts only;
- runtime-owned storage adapters in a distinct outward target.

Runtime does not import concrete policy engines, providers, operators, renderers or transports.

### AuralisReceipts

The first physical receipts consolidation landed on 2026-10-24: `ArtifactCore` and
`ArtifactStorage` moved into the `ReceiptsCore` package as independent products and test targets.
This keeps artifact contracts and persistence in their final receipts owner while allowing Runtime
to remain inward-only. The owner package passed 162 tests, five direct consumers passed 627 tests,
the package-graph guard passed, and Xcode build-for-testing succeeded.

`ReceiptStorage` then joined the same package as an independent product and test target. The Xcode
project now links that product from the existing ReceiptsCore package reference rather than carrying
a second local package root. All 369 owner-package tests are green, its three direct consumers passed
198 tests, the package-graph guard passed, and Xcode build-for-testing succeeded.

### AuralisContext

Own current-context assembly and durable memory as different targets:

- `ContextCore` and `ContextLive`;
- `MemoryCore` with provenance, sensitivity, retention, correction, deletion and portability;
- `MemoryStorage` implementations;
- `MemoryRetrieval` that contributes governed fields to task context.

Writing memory is an explicit operation. Context assembly has no implicit persistence side effect.

### AuralisPolicy

Own authority evaluation, delegation rules, consent boundaries, policy modes, limits, leases where
policy-owned, revocation and autopilot authorization. Policy emits a typed decision/evidence event;
the governed host records required receipts before consequential execution.

### AuralisReceipts

Own receipt and artifact values, stores, integrity, export, provenance and presentation.
`ReceiptJSONValue`, `ReceiptPayload`, and `ReceiptMode` moved here on 2026-10-23 with
backward-compatible encoding tests. `ReceiptActor`, `ReceiptActorDetail`, and
`ReceiptAuthorityDetail` plus their Runtime conversion bridge also moved here on 2026-10-23 after
Policy adopted canonical `RuntimeCore.ActorRef`. Runtime now exposes a persistence-neutral tolerant
reconstruction initializer and has no receipt dependency. Artifact and receipt causality remains
explicit and typed.

### AuraPlayEngines

`AuraPlayMediaCore`, `AuraPlayAudioEngine`, and `AuraPlayVideoEngine` consolidated into one package
root on 2026-10-23 while retaining their module/product names, separate targets, demo executables,
and test targets. Audio and video still depend only on MediaCore internally; the merge changes
physical package ownership, not the public playback contracts. The consolidated package passed all
186 independent tests (77 video, 37 media-core, 72 audio). After the Xcode local-package references
were replaced, build-for-testing passed and the two package/import architecture guards plus all 22
AuraPlay orchestration tests passed (24/24 focused app tests).

### AuralisCrypto

Own Ethereum/account/chain/token/NFT/wallet values and adapters. Generic runtime checks remain in
Runtime; Ethereum resolution and crypto-specific checks live here and register through Runtime
protocols. Vendor SDKs remain isolated in leaf targets.

### AuralisOperators

Own concrete tools/operator packs, music domain/persistence, social behavior, provider-specific model
inference adapters and future transport adapters. Provider adapters implement Runtime inference
contracts but remain independent of individual operator targets.

### MissionControl, AuraUI and AppShell

Runtime owns presentation-independent trusted-UI schemas. Mission Control owns reusable trusted
rendering, approval and intervention surfaces. AuraUI supplies design primitives. AppShell composes
all selected concrete implementations and owns process-wide `RuntimeHost`.

## Canonical Operator Manifest

The eventual Swift API must represent these ten static responsibility groups:

1. identity and purpose;
2. context and permitted memory access;
3. reasoning/planning capabilities and boundaries;
4. capabilities, tools, inputs, outputs and effects;
5. requested authority, risk and confirmation boundaries;
6. supported commitment types and recovery behavior;
7. event categories, triggers and idempotency;
8. artifacts, receipts, evidence and provenance;
9. success verification, failure and escalation;
10. UI representations, intervention surfaces, lifecycle and compatibility.

The manifest supports explicit absence of inference, scheduling or memory. It contains no current
permission, live context, active commitment or execution progress. Registration never grants
authority.

## Migration Gates

Before moving sources into any aggregate package:

1. Record the final target and product list for that package.
2. Record allowed imports for every target.
3. Move consumer-owned protocols inward before moving implementations.
4. Add explicit domain/adaptor conversion tests where models split.
5. Preserve `Sendable`, actor isolation, cancellation and typed error behavior.
6. Move existing tests with their owner; do not widen production access only for tests.
7. Run each affected target/package test suite, then the full app test plan.
8. Build the Auralis scheme.
9. Update architecture import scanners and package ownership documentation.
10. Verify no new public type duplicates an existing runtime primitive.

## External Publication

The 12-package plan does not prohibit future open-source extraction. A target is a candidate only when
there is a concrete external consumer and it already has:

- a coherent API independent of Auralis app models;
- tests and supported-platform declarations;
- no sibling-source assumptions;
- no secret, asset, localization or process-singleton dependency;
- an honest dependency graph and license review.

Until then, target independence is sufficient and avoids replacing 41 manifests with a new release
management problem.

## Completion Criteria

ARCH-004 is complete when:

- all 12 packages use the target graph in ARCH-003;
- every domain model has one recorded owner;
- domain targets depend on protocols rather than concrete adapters;
- generic algorithms remain local and do not infect host/UI APIs;
- Runtime has no concrete provider/operator/UI dependency;
- policy is decoupled from receipt persistence without weakening fail-closed execution;
- Mission Control depends on operator registry contracts, not packs;
- memory and commitments exist as distinct, tested domains;
- existing event, outcome, model-routing, identity, generated-UI, receipt and artifact primitives were
  moved/adapted rather than duplicated;
- architecture tests reject all prohibited imports.
