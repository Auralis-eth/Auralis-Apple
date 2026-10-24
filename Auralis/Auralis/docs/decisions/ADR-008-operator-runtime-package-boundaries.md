# ADR-008: Operator Runtime Package Boundaries

## Status

Accepted.

## Context

The operator runtime added a set of new Swift packages. Without an explicit boundary rule they would
drift into cycles or drag heavy dependency graphs (ENS/secp256k1/web3.swift) into leaf logic packages,
breaking isolated `swift test`.

## Decision

Layering, low → high (a package may depend only on packages above it in this list):

1. **Leaf models/vocabulary:** `AuralisPrimaryModels`, `CapabilitiesCore`.
2. **Kernel primitives:** `RuntimeCore` (ActionProposal, ImpactClass, JudgeDecision, ToolDefinition/
   Registry, GovernedToolPipeline, DeterministicCheck, Worklog, EventBus, ActorRef, ContextBundle,
   CapabilityLease, PauseGate, ReceiptSigner, model routing, eval stubs). Depends only on layer 1 + system
   frameworks (Foundation/CryptoKit). **Must never import ENS/secp256k1/web3 or any UI.**
3. **Domain cores:** `ReceiptsCore`, `ArtifactCore`, `PlaybookCore`, `PerformanceCore`, `SchedulingCore`.
4. **Storage:** `ReceiptStorage`, `ArtifactStorage` (SwiftData).
5. **Policy/planner:** `PolicyCore`, `PlannerCore`, `AutopilotCore` (hosts `DomainJudge`, the planner-ladder
   bridge).
6. **Operators:** `OperatorsFeature` (ToolDefinitions + executor).
7. **App host:** `RuntimeKit` — owns the process-wide singletons (event bus, registries, pause gate,
   playbook/artifact/performance stores, scheduling engine) and the receipt sink; the only place that wires
   the kernel to storage + policy.
8. **UI:** `AuraUI` (design system + A11yID), `MissionControlFeature` (operator console).
9. **App target.**

Rules:

- `RuntimeCore` stays a light, bare-`swift test`-able leaf. `ActorRef` lives here. The empty
  `AgentIdentityCore` placeholder and its unused ENS/secp256k1 dependency graph were removed rather
  than preserving a package with no domain ownership.
- Only app-linked packages get an `XCLocalSwiftPackageReference` in the project; transitive packages are
  resolved by SwiftPM. Today the app links `RuntimeKit` + `MissionControlFeature`; everything else is
  transitive.
- Enforcement: each core/kernel package must build and test in isolation via
  `DEVELOPER_DIR=<Xcode-beta> swift test`. A package that can't is a boundary violation.

### Execution isolation contract

The shipping runtime provides **capability isolation for trusted code in the Auralis process**.
App callers enter through `RuntimeHost` and `GovernedToolPipeline`, which resolve registered tools,
validate schemas, enforce capability and impact declarations, apply leases and restrictions, invoke
the judge, and write receipts around execution. Direct app-to-executor calls are forbidden by
architecture tests.

This boundary is not an OS process sandbox and does not authorize loading hostile native plugin code
into the app process. Before Auralis accepts untrusted native executors, they must move behind a
separately reviewed XPC or Enhanced Security extension boundary. That host must expose a narrow
value-based request/response protocol, retain wallet signers, Keychain secrets, SwiftData contexts,
and receipt-signing keys in the trusted process, and validate returned data as untrusted before it is
used or receipted.

## Consequences

Every kernel/domain package is independently verifiable, which is how the operator runtime was built and
tested without the app target. New packages must slot into a layer and respect the import direction.

Boundary tests in the app test target enforce the allowed import graph so package drift fails in CI.

Release CI selects the `Auralis-Full` test plan explicitly. The fast plan is an iteration tool and is
not evidence that the complete release matrix ran.
