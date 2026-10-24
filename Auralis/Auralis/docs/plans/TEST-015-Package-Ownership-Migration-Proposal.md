# TEST-015: Test Ownership Migration For The 12-Package Architecture

Status: In progress; re-scoped from the original package-by-package proposal
Date: 2026-10-22
Related: `ARCH-003-Domain-Package-Consolidation-Plan.md`, `ARCH-004-Independent-Core-And-Adapter-Migration-Plan.md`

## Purpose

Tests belong with the target that owns the behavior. A green app test plan is not evidence that local
package targets compile or that their contracts are independently protected.

This revision targets the approved 12 Auralis-owned packages directly. It does not move a test into an
intermediate package merely to move it again during consolidation. `CodeScanner` remains vendored and
keeps its own tests; third-party tests are outside this plan.

## Rules

1. Domain behavior is tested in the owning domain target.
2. Adapter behavior is tested beside the adapter, using the domain protocol as its boundary.
3. The app target keeps composition, schema-assembly and cross-package integration tests only.
4. Existing mixed tests are split; they are not copied wholesale.
5. No package test imports the app module.
6. `AuralisTestSupport` remains dependency-clean and may depend only on AuralisFoundation.
7. Receipt/SwiftData/provider-specific fixtures remain in their owning package tests rather than
   pulling those dependencies into shared test support.
8. Test moves preserve or improve cancellation, actor-isolation, error and compatibility coverage.

## 2026-10-22 Source Inventory

### Work already completed

| Behavior | Current evidence | Final destination |
|---|---|---|
| NFT refresh-state calculation | `NFTKit/Tests/NFTKitTests/NFTRefreshStateComputerTests.swift` | `AuralisCrypto.NFTDomainTests` |
| NFT metadata update/preparation | `NFTMetadataUpdaterTests`, `PrepareNFTMetadataUseCaseTests` in NFTKit | `AuralisCrypto.NFTDomainTests` / adapter tests according to imports |
| NFT inventory fetch/persist/service | Package-local NFTKit tests now exist | Split across `NFTDomainTests`, `NFTProviderAdapterTests`, `NFTPersistenceTests` |
| Music collection/item presentation | Package-local MusicFeature tests exist | `AuralisOperators.MusicPresentationTests` |
| Music library indexing and receipt logging | Package-local `MusicLibraryIndexTests` and `MusicReceiptEventLoggerTests` exist | Music persistence tests and AuralisReceipts integration tests as appropriate |
| Account storage | `AccountStorage` has SwiftData store tests and test containers | `AuralisCrypto.AccountStorageTests` |
| Basic account contracts | `AccountsCoreTests` exists | `AuralisCrypto.AccountsTests` |
| Primary ownership vocabulary | `OwnershipVocabularyTests` exists | `AuralisFoundation.OwnershipCoreTests` |
| Basic AuraUI colors | `AuraColorTests` exists | `AuraUITests` |
| CodeScanner basics | Existing CodeScanner package tests | Remain in vendored CodeScanner |
| Explicit package platforms | Touched packages now declare iOS/macOS floors, including AccountStorage | Preserve during manifest consolidation |

### Known remaining app-owned behavior suites

The source inventory still found these package-behavior names in `AuralisTests`:

- `NFTProviderFailurePresentationTests.swift`
- `ProviderAbstractionTests.swift`
- `ChainTests.swift`
- `EOAccountTests.swift`

Each must be split by imports and behavior before removal. App assembly/provider-selection assertions
remain in renamed integration suites.

### Structural blocker

The `AuralisTestSupport -> ReceiptStorage` blocker was removed on 2026-10-22. `StoredReceiptFixture`
is app-integration-only and now lives in `AuralisTests`; an architecture test rejects reintroducing
the manifest or source import. Before Phase 1, continue to:

- move them into `AuralisReceipts` test support;
- keep only generic clocks, deterministic IDs/dates, dependency-free builders and legal Foundation
  fixtures in `AuralisTestSupport`.

## Final Test Ownership Matrix

| Production responsibility | Owning package/target tests | App tests retain |
|---|---|---|
| Primitives, principal IDs, ownership and capabilities | `AuralisFoundation` target tests | Primary app schema membership only |
| Runtime tools, hooks, events, sessions, attribution and checks | `AuralisRuntime.RuntimeCoreTests` | Live host wiring only |
| Intent and commitment lifecycle | `IntentCoreTests`, `CommitmentCoreTests` | End-to-end composition smoke tests |
| Plans, playbooks, scheduling, runtime state | Corresponding AuralisRuntime target tests | App-selected registrations/configuration |
| Model routing/inference contracts | `InferenceCoreTests` | `ModelProviderComposition` routing smoke tests |
| Outcome verification and evaluation | `OutcomeVerificationTests`, `EvalTests` | Mission Control presentation integration |
| Operator manifest/registry | `OperatorRegistryTests` | Concrete-pack registration through AppShell |
| Receipt values, integrity, export and storage | AuralisReceipts core/storage tests | App receipt-recorder bridges |
| Artifacts and artifact storage | AuralisReceipts artifact target tests | Cross-feature artifact navigation only |
| Context snapshots, freshness, provenance and assembly | AuralisContext context tests | Live app source composition |
| Memory retention, correction, deletion, retrieval and portability | AuralisContext memory target tests | User-facing reset/export wiring |
| Policy, delegation, consent and revocation | AuralisPolicy target tests | Governed-host evidence sequencing |
| Account/chain/provider/ENS/token/NFT/wallet behavior | AuralisCrypto target tests | Live provider selection and app callbacks |
| Concrete operators and provider adapters | AuralisOperators target tests | App-selected pack composition |
| Music domain, persistence and presentation | AuralisOperators music target tests | Shell navigation/playback composition |
| Trusted rendering and Mission Control state | MissionControl target/snapshot tests | Top-level shell presentation only |
| Shell state, routing and Search persistence | AuralisAppShell target tests | App lifecycle and full scene wiring |
| Audio/video/media contracts | AuraPlayEngines target tests | Selected-engine composition |
| Design primitives and accessibility identifiers | AuraUI tests | Full-screen integration/snapshots where necessary |

## Required New Contract Tests

### Concept boundaries

- inferred intent cannot become an authorized commitment without an authorization transition;
- plan construction grants no capability or authority;
- successful tool execution does not close a commitment without outcome verification;
- context assembly cannot write durable memory implicitly;
- artifact and receipt IDs/references cannot substitute for one another;
- revocation is rechecked before execution and prevents subsequent action;
- receipt evidence is evaluated against commitment success criteria.

### Operator manifest

- all ten responsibility groups round-trip through the versioned manifest representation;
- inference, memory and scheduling can be explicitly absent;
- registration does not create a capability lease or policy grant;
- live permissions, context, progress and active commitments are not serialized as static manifest;
- unknown future fields/versions follow a documented compatibility policy;
- removing a concrete pack requires no source change in Mission Control.

### Memory

- provenance survives persistence and retrieval;
- retention and deletion are enforced;
- correction does not silently rewrite audit history;
- sensitivity/data-scope rules filter retrieval;
- cancellation propagates through async retrieval;
- temporary context is not retained without an explicit memory-write use case.

### Commitments and outcomes

- lifecycle covers amendment, cancellation, delegation, expiration, escalation and fulfillment;
- runtime attempts/retries remain separate execution records;
- dependencies and idempotency survive restoration;
- outcome verification can keep a commitment open after a successful request;
- evidence absence, contradiction and late confirmation have deterministic results.

## Migration Slices

### Slice 0 — Test infrastructure and baseline

- [x] remove the `AuralisTestSupport -> ReceiptStorage` dependency;
- [x] add an architecture test that rejects the reverse dependency;
- [x] record the app baseline: build-for-testing passed; `Auralis-Full` ran 961 tests with 955 passed,
  4 skipped and 2 pre-existing Dynamic Type audit failures (`Music`, `Receipts`);
- [x] verify the first cut: the 22 directly affected tests passed, and the post-change `Auralis-Full`
  run completed with 962 tests, 958 passed, 4 skipped and 0 failed. The additional test is the new
  package-boundary guard; the two baseline Dynamic Type audit failures did not reproduce;
- record all 42 current local-root test results or documented blockers;
- add the required package-test CI lane;
- retain current snapshot and receipt golden-vector baselines.

### Slice 1 — Foundation model split

- [x] consolidate the media, audio, and video engine roots into `AuraPlayEngines` without collapsing
  their target/test boundaries (2026-10-23); all 186 package tests passed, build-for-testing passed,
  and the package/import guards plus all 22 AuraPlay orchestration tests passed (24/24 focused tests);
- [x] move `PrincipalID`, `OwnershipDescriptor`, and all 20 ownership tests to the final
  dependency-free `AuralisFoundation` package (2026-10-23);
  validation: Foundation 20/20, remaining PrimaryModels 10/10, ReceiptsCore 68/68,
  ReceiptStorage 207/207, build-for-testing passed, and the full app plan ran 962 tests with 956
  passed, 4 skipped, and only the same 2 intermittent Dynamic Type audit failures from the baseline;
- [x] move the unchanged `CapabilitiesCore` module/product and its independent tests into
  `AuralisFoundation` (2026-10-23); Foundation passed 24/24, RuntimeCore 240/240, PolicyCore 10/10,
  MusicFeature 133/133, build-for-testing passed, and both package/import guards passed;
- [x] move the generic `SwiftDataAdapters` and `UserDefaultsAdapters` modules and their independent
  tests into `AuralisFoundation` (2026-10-23), removing the UserDefaults suite's reverse dependency
  on `AuralisTestSupport`; Foundation passed 34/34, the four SwiftData consumers passed 248/248
  combined, build-for-testing passed, and both package/import guards passed;
- move `ChainTests` and `EOAccountTests` to AuralisCrypto, not Foundation;
- [x] move `TokenHoldingsMetadataFreshnessPolicy` to its current final-owner target, `TokenStorage`
  (2026-10-23); PrimaryModels passed 10/10, TokenStorage 10/10, build-for-testing passed, and the
  ownership guard plus both app presentation consumer suites passed (22/22 focused tests);
- [x] move app-launch-only `PrimaryStoreCopy` out of PrimaryModels and into app composition
  (2026-10-23); build-for-testing and the ownership guard passed;
- [x] move generic `JSONValue` into `AuralisFoundation` and retire MusicFeature's duplicate private
  implementation (2026-10-23); Foundation passed 23/23, PrimaryModels 10/10, NFTKit 52/52,
  ProviderKit 22/22, MusicFeature 133/133, AuralisTestSupport built, build-for-testing passed, and
  both architecture guards passed;
- [x] delete the unconsumed `NFTIdentity`, `NFTMetadataSnapshot`, `TokenHoldingDescriptor`,
  `PlaylistDescriptor`, and `SearchHistoryValue` placeholders instead of preserving speculative APIs
  in their planned owner targets (2026-10-23); build-for-testing and the package-graph/ownership guard
  passed. The guard rejects their return without real consumers;
- [x] strengthen the account-removal undo contract before splitting persistence owners (2026-10-23):
  restore deleted `MusicLibraryItem` rows and the NFT attributes already captured by the snapshot;
  build-for-testing and the focused account-removal undo integration test passed. A matching
  owner-package test now lives in `AccountStorageTests`; the generated Xcode package scheme builds
  but currently exposes zero runnable tests, so execution remains pending the required package-test
  CI/`swift test` lane rather than being reported as passed;
- [x] introduce transaction participants for token, music, search, and NFT capture/delete/restore
  behavior without allowing participants to save or open transactions (2026-10-23); build-for-testing
  and four focused overwrite/removal/undo/architecture checks passed;
- [x] add deterministic failure injection proving a participant failure rolls back every preceding
  participant (2026-10-23); the first run exposed that SwiftData typed batch deletes permanently
  removed token and music rows despite `ModelContext.rollback()`. Replacing account-scoped batch
  deletion with fetched per-model deletion made the failure test pass; build-for-testing and the four
  existing account/architecture regressions also pass;
- [x] move token account-lifecycle snapshot/delete/restore behavior into TokenStorage and NFT
  lifecycle behavior plus orphan pruning into NFTPersistence using the generic Foundation protocol
  (2026-10-23); build-for-testing and five focused rollback/undo/overwrite/graph/layer checks passed;
- [x] expand NFT undo fidelity coverage to image/raw child records, external/background metadata,
  tags, and playlist membership (2026-10-23); the first run exposed eight lost values/relationships,
  NFTPersistence restoration was repaired, and both undo plus forced-rollback tests pass;
- [x] move `AccountSummary` to AccountsCore and remove the empty mixed portable-values source; move
  music-only `NFT.musicURL` plus remote audio normalization into MusicFeature; move native-token
  `Chain` presentation into TokenStorage (2026-10-23); build-for-testing and focused ownership,
  undo, and rollback checks pass;
- [x] move `ReceiptJSONValue`, `ReceiptPayload`, and `ReceiptMode` plus explicit wire compatibility
  tests to ReceiptsCore (2026-10-23); validation:
  PrimaryModels 10/10, ReceiptsCore 71/71, PolicyCore 10/10, ReceiptStorage 207/207,
  build-for-testing and the ownership guard passed, and the full app plan ran 963 tests with 958
  passed, 4 skipped, and only the existing intermittent Music Dynamic Type audit failure;
- [x] replace receipt-shaped Policy attribution with `RuntimeCore.ActorRef`, then move
  `ReceiptActor`, `ReceiptActorDetail`, `ReceiptAuthorityDetail`, their conversion bridge, and the
  bridge tests into ReceiptsCore (2026-10-23), preserving Receipts → Runtime and prohibiting the
  reverse edge; RuntimeCore passed 240/240 tests, ReceiptsCore passed 115/115 tests, the Xcode
  build-for-testing passed after RuntimeCore was declared directly on `AuralisTests`, and the four
  focused ownership/policy integration tests passed. The subsequent full-plan runner remained active
  without producing a result and was cancelled after the package and focused evidence was captured;
- [x] add conversion tests and move `MusicLibraryItem`, its domain values, and its account lifecycle
  participant into MusicFeature (2026-10-24). AccountStorage consumes a type-erased participant from
  app composition instead of importing the macOS-26 MusicFeature package, preserving the intended
  Crypto → Operators dependency direction. MusicFeature passed 136/136, AccountStorage 10/10,
  PrimaryModels 10/10, eight focused app architecture/removal/overwrite/undo/rollback tests passed,
  and Xcode build-for-testing succeeded.
- [x] move `SearchHistoryRecord`, its complete snapshot, and its account lifecycle participant into
  the app-owned Search domain (2026-10-24). AccountStorage now consumes Search through the same
  type-erased participant seam and retains no Search model fields. AccountStorage passed 10/10,
  PrimaryModels passed 10/10, eleven focused schema/scope/architecture/removal/overwrite/undo/rollback
  tests passed, and Xcode build-for-testing succeeded.
- [x] preserve `PlannerCore` and `PlannerCoreTests` as independent module/test targets while moving
  them into the `RuntimeCore` package root (2026-10-24). Planner passed 35/35, Autopilot 35/35,
  RuntimeKit 284/284, Mission Control 126/126, and Xcode build-for-testing succeeded. The package
  graph guard rejects restoration of the standalone PlannerCore root.
- [x] preserve `PlaybookCore` and `PlaybookCoreTests` as independent module/test targets while
  moving them into the `RuntimeCore` package root (2026-10-24). The output-kind contract moved
  inward as `ArtifactOutputType`, with `ArtifactType` retained as a receipts-side alias, avoiding
  the Runtime → Receipts → Runtime package cycle without moving ArtifactCore out of its final owner.
  Runtime/Planner/Playbook passed 286/286, ArtifactCore 21/21, seven consumer suites passed 838/838,
  the focused graph guard passed, and Xcode build-for-testing succeeded.
- [x] preserve `PerformanceCore` and `PerformanceCoreTests` as an independent module/test target
  while moving them into the `RuntimeCore` package root (2026-10-24). RuntimeCore passed 314/314;
  OperatorRuntimeStorage, RuntimeKit, SchedulingCore, Mission Control, and EvalCore passed 566/566;
  the graph guard and Xcode build-for-testing passed.
- [x] preserve `EvalCore` and `EvalCoreTests` as an independent module/test target while moving
  them into the `RuntimeCore` package root (2026-10-24). RuntimeCore passed 363/363 and its three
  direct consumers passed 466/466; the graph guard and Xcode build-for-testing passed.

### Slice 2 — Runtime consolidation

- preserve the existing RuntimeCore, Planner, Playbook, Scheduling, Performance and Eval suites as
  separate test targets;
- add intent/commitment boundary tests before introducing their production types;
- move Ethereum check tests with the checks into AuralisCrypto;
- test model routing without concrete providers.

### Slice 3 — Receipts, context and memory

- [x] preserve `ArtifactCore`, `ArtifactStorage`, and their independent test targets while moving
  them into the `ReceiptsCore` package root (2026-10-24). The owner passed 162/162, five direct
  consumers passed 627/627, the graph guard passed, and Xcode build-for-testing succeeded;
- preserve every receipt envelope golden vector unchanged;
- keep storage/tamper/export compatibility tests distinct from receipt UI tests;
- move current app Context tests with extracted ContextCore;
- add Memory tests from the required list above.

### Slice 4 — Policy decoupling

- replace direct receipt-store policy tests with policy decision-event tests;
- add governed-host integration tests proving required evidence is durably recorded before execution;
- prove recorder failure fails closed for consequential actions;
- cover revocation between planning, approval and execution.

### Slice 5 — Crypto

- finish splitting `ProviderAbstractionTests` by ProviderKit, ChainProviders and NFT adapter ownership;
- move the remaining NFT failure-presentation behavior;
- keep vendor SDK adapter tests isolated from wallet-contract tests;
- retain physical-device wallet QA as separate evidence, not a compile-time unit-test claim.

### Slice 6 — Operators and Mission Control

- migrate existing operator catalog tests into canonical manifest/registry tests;
- keep concrete operator execution/provider-adapter tests in AuralisOperators;
- remove concrete pack imports from Mission Control tests;
- preserve trusted-UI fidelity, redaction and approval tests.

### Slice 7 — Shell and final cleanup

- move Search persistence/routing tests into AppShell targets;
- rename remaining app suites to make composition scope explicit;
- verify no package-owned behavior suite remains in `AuralisTests`;
- update test plans and architecture scanners for the 12-package graph.

## Validation Per Slice

- affected package test targets pass independently;
- all previously independent test targets remain separate;
- `Auralis` builds;
- `Auralis-Full` passes;
- architecture/import tests pass;
- Swift concurrency warnings do not increase;
- snapshot changes are explained rather than automatically re-recorded;
- receipt integrity golden vectors do not change unless a new envelope version is deliberately added;
- app tests removed in the slice have equivalent or stronger final-owner coverage.

## Completion Checklist

- [ ] Shared test support depends only on AuralisFoundation.
- [ ] All package manifests declare compatible platforms.
- [ ] Every final production target has an owning test target or a documented reason it does not.
- [ ] Intent, commitment, runtime-state, memory, context, artifact and receipt boundaries are tested.
- [ ] Operator manifest authority/absence/runtime-state rules are tested.
- [ ] Existing NFT and music package migrations survive movement to final packages.
- [ ] Provider, chain, account and NFT failure tests no longer remain as package behavior in app tests.
- [ ] App tests are explicitly composition/integration/architecture/UI suites.
- [ ] CI runs all final package suites as a required lane.
- [ ] The full app test plan and Auralis build pass after every consolidation phase.
