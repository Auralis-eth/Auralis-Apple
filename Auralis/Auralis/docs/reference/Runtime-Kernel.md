# Runtime Kernel — Contract Reference

The nine primitives that make agent work in Auralis governable. This is **reference**, not a plan:
it describes the kernel as it currently is, independent of the phase that built it. Read it when you
are adding a tool, a check, an event consumer, a context source, or any new surface that acts on the
user's behalf.

Each primitive below states **what it is**, **where it lives**, **the invariant it enforces**, **what
proves the invariant**, and **its known limits**. Where an invariant is enforced by the compiler or by
a test rather than by convention, that is called out — those are the ones you cannot accidentally
regress.

Companion docs: `ADR-008` (package boundaries + execution-isolation contract), `ADR-004` /
`ADR-010` (Observe/Assist/Operate and the crypto-scoped boundary), `ADR-003` (local data
classification). Device- and review-gated residuals live in `plans/Phase-1-Known-Limitations.md`.

---

## How the primitives compose

One path, in this order. Nothing skips a stage:

```
proposal → resolve tool → validate schema → deterministic checks → judge
         → [escalate → human approval → resume] → execute → receipt → worklog + events
```

`GovernedToolPipeline` (`RuntimeCore/Hooks/`) owns that sequence. Callers enter through
`RuntimeHost`; they do not assemble the stages themselves and cannot reach an executor directly.

`RuntimeHost.bootstrap()` is the kernel's assembly-time gate. It `precondition`s on four things, so a
misconfigured kernel fails at launch rather than mid-workflow:

| Bootstrap precondition | What it prevents |
|---|---|
| No duplicate tool IDs across operator + policy catalogs | A tool silently shadowing another |
| No duplicate check IDs across the three check sets | A governance check being silently replaced by a same-ID impostor that still reports a pass |
| Every tool's `requiredCheckIDs` resolves to a registered check | A tool declaring a check that never runs |
| Every non-`readOnly` tool has `requiresReceipt` | A state-changing action leaving no evidence |

---

## 1. Action Boundary

**What.** Nothing acts directly. An intent becomes an `ActionProposal` — actor, capability,
parameters, correlation ID — carrying an `ActionImpactClass` (`readOnly`, `reversibleWrite`,
`externalImpact`, `highRisk`). A `Judge` returns a `JudgeDecision`: `allow`, `block`, `revise`, or
`escalate` (with an `ApprovalRequest`).

**Where.** `RuntimeCore/Action/`, `RuntimeCore/Judge/`.

**Invariant.** Impact classification precedes authority. The impact class is a property of the *tool
definition*, not of the caller's claim about itself, so a caller cannot describe a `highRisk` action
as `readOnly` to route around gating.

**Proof.** `ArchitectureBoundaryTests` fails the build if app source calls a tool executor directly,
bypasses the policy pipeline, or composes/mutates the governed runtime. A companion test restricts
runtime composition to `RuntimeKit` across all first-party packages. `ActionImpactClass` and
`CapabilityImpactMapping` suites cover the classification itself.

**Limits.** This is capability isolation *inside the app process*, not an OS sandbox. Hostile native
plugin code needs an XPC or Enhanced Security extension first — see ADR-008 §Execution isolation.

## 2. Tool Registry + Hooks

**What.** A `ToolDefinition` declares id, title, capability, impact, input/output `ToolSchema`,
`requiredCheckIDs`, and `requiresReceipt`. `ToolRegistry` is the only source of executables.
`BeforeToolCallHook` / `AfterToolCallHook` observe and can veto; `GovernedToolPipeline` runs the whole
sequence.

**Where.** `RuntimeCore/Tools/`, `RuntimeCore/Hooks/`.

**Invariant.** Nothing executes outside the registry, and nothing executes outside the pipeline.
Schemas are validated against the declared shape before any check or judge runs, and `ToolSchema`
closes over additional fields by default (`allowsAdditionalFields`, with explicit
`allowedAdditionalFieldPrefixes` where a family of keys is genuinely open).

**Proof.** RuntimeCore's `GovernedToolPipelineTests`, `ToolHookContractTests`, and the
`DeterministicCheckRegistry` suite in `PrimitivesTests.swift`; the bootstrap preconditions above; the
boundary tests in §1.

**Limits.** Hook veto is advisory over ordering, not a second policy engine — put real authority
decisions in the Judge or in a deterministic check, where they are recorded as evidence.

## 3. Runtime Event Bus

**What.** `RuntimeEventBus` is an actor fanning `WorkflowEventEnvelope`s out over `AsyncStream`.
It offers **two deliberately different contracts**:

| Contract | API | For | Semantics |
|---|---|---|---|
| Bounded live | `events()` | UI / activity feeds | May drop under burst; latest state matters more than completeness |
| Named lossless | `reliableEvents(...)` | Receipt + performance observers | Durable per-subscriber checkpoints, history replay, no silent drops |

`subscriberHealth()` exposes lag and drop state so a starved audit consumer is visible rather than
merely quiet.

**Where.** `RuntimeCore/Events/`.

**Invariant.** Audit-critical consumers must use the reliable contract and must surface their health
in Mission Control. A dropped event on the bounded stream is a UI cost; a dropped event on an audit
path is a hole in the record.

**Proof.** `RuntimeEventBusTests` covers burst-without-drops for reliable subscribers, concurrent
publishers with no loss or duplication, and removal of terminated subscriptions.

**Limits.** Event history is capped (matched to the worklog cap). The bus is in-process; it is not a
cross-device or cross-process transport.

## 4. Context Bundles

**What.** A `ContextBundle` is the typed, provenance-carrying input to model and tool work: fields
with a source, a data class, and a `refreshedAt`. A `ContextBundleContract` validates a bundle
against declared requirements — freshness windows, required fields, data classes, allowed sources —
and yields a `GovernedContext` that downstream code can consume.

**Where.** `RuntimeCore/Context/`.

**Invariants.**
- **Validated context cannot be forged outside RuntimeCore.** The only way to hold a `GovernedContext`
  is to have passed the contract.
- **Model workflows cannot attach raw dictionaries.** Context reaches inference through the
  authorization factory, never as an untyped bag.
- **Freshness is re-checked at resume, not just at proposal.** An approval cleared after its freshness
  window has lapsed is refused rather than executed against stale facts.
- **Missing/extra fields have declared behavior**, not ad-hoc handling: `MissingFieldBehavior`
  (`fail` / `useStale` / `proceedWithoutField`) and `AdditionalFieldBehavior` (`reject` / `omit`).
- **Sensitive fields travel as references.** `.sensitiveReference` fields are never rendered raw;
  trusted UI redacts them at the presentation boundary.

**Proof.** `validatedContextConstructionStaysInsideRuntimeCore`,
`modelInferenceContextMustUseAuthorizationFactory`, and the Foundation-Models governed-prompt test in
`ArchitectureBoundaryTests`; RuntimeCore's `ContextBundleContract` suite (in `PrimitivesTests.swift`)
and `ContextFreshnessBoundaryTests`. `configurationViolations()` catches self-contradictory contracts (e.g. a required field
the contract also omits) and `evidenceDigest()` makes the validating contract itself part of the
record.

**Limits.** `maximumFutureSkew` bounds clock-skew tolerance but cannot detect a deliberately wrong
device clock.

## 5. Trusted UI Requests

**What.** Agent-initiated UI is a **request**, not a rendered view. `TrustedUIRequest` is a closed
enum (`approveAction`, `editDraft`, `inspectCapability`, `reviewReceipt`, `inspectContextBundle`,
`presentSuggestion`, `presentRiskBanner`). `TrustedUIKit`'s `TrustedUIComponentRegistry` maps each
case onto exactly one audited component: PermissionCard, SuggestionCard, ApprovalSheet, ReceiptCard,
RiskBanner, ContextBundleCard, DraftEditorCard.

**Where.** `RuntimeCore/TrustedUI/` (the request schema), `TrustedUIKit` (the registry + components),
consumed via `MissionControlFeature.TrustedUISurface`.

**Invariant.** An agent can ask for a known trust surface; it cannot draw one. The mapping is a closed
switch, so a request has one auditable rendering and operator/playbook packages cannot ship arbitrary
platform UI.

**Proof.** `trustedUIRequestsHaveProductionRoutes` fails if any core request lacks a production route;
`operatorPackagesCannotRenderArbitraryUI` keeps operator/playbook packages out of the UI business.
`TrustedUIComponentRegistry` suites cover governed mapping, resolution, and impact→risk-level
derivation.

**Limits.** Mission Control keeps some richer bespoke chrome (navigation, filters, accessibility IDs)
alongside the generic components; those surfaces are feature supersets, and replacing them wholesale
with the generic components would regress the product. Consequence: two rendering paths exist for a
few surfaces, and the trusted one is authoritative for *trust* content (risk, redaction, decision
controls).

## 6. Actor Attribution

**What.** Every recorded act answers three questions:

| Question | Type | Values |
|---|---|---|
| Who acted | `ActorRef` | `human`, `operator`, `plugin`, `workflow`, `scheduledRoutine`, `model` (with `InferenceProvenance`: locality, provider, model class) |
| Under what authority | `AuthorityRef` | `lease`, `humanApproval`, `policyDefault` |
| Through what workflow | `correlationID` | the trace key that stitches steps into a workflow |

Attachment points: `ActionProposal`, every `WorkflowStepLog` event kind, `ExecutionRecord`,
`AgentSession`, and receipts (first-class structured columns covered by the chain hash).

**Where.** `RuntimeCore/Actor/`, `RuntimeCore/Action/`.

**Invariant.** Attribution is **compiler-enforced**. `actorDetail`, `authorityDetail`, and
`correlationID` are required, non-defaulted parameters — a new writer cannot omit attribution and
still compile. `authority` is legitimately `nil` only pre-authority (proposal, checks, judge) and on
blocked receipts, since all three `AuthorityRef.Source` values mean "permitted".

**Proof.** The type signatures themselves, plus `ActorAttributionTests.swift` (ActorKind
serialization stability, ActorRef identity, AuthorityRef, ModelRoute attribution bridge) and
`runtimeSourcesDoNotAttributeWorkToAnonymousActor`, which bans the anonymous `ActorRef.system` in
runtime sources so work cannot be attributed to nobody.

**Limits.** Decoding is deliberately tolerant in both directions — a missing actor falls back to
`.system`, an unreadable authority degrades to "not recorded" — rather than dropping the enclosing
row. Attribution names the *seam that ran*: do not stamp remote/provider telemetry unless provider
inference actually happened; local fallbacks must stay visibly local.

## 7. Worklogs

**What.** The durable narrative of what the runtime did. `WorkflowStepLog` entries carry a
`WorkflowWorklogEvent`: `considered`, `proposed`, `checksEvaluated`, `decided`, `executed`, `blocked`,
`failed`, `routinePhase`. Written by `GovernedToolPipeline`, `SchedulingEngine`, `AutopilotRunner`,
and Mission Control stop; read by `MissionControlDerivations` as the **primary** source of workflow
state.

**Where.** `RuntimeCore/Worklog/` (+ `InMemoryWorklog`); durable via
`OperatorRuntimeStorage.SwiftDataWorklogStore`.

**Invariants.**
- **Forward compatibility never loses data.** An unrecognized event kind, payload, or routine phase
  decodes as `unknown(caseName:payload:)`. The entry survives with its attribution intact; the payload
  survives verbatim in `WorklogRawJSON` and re-encodes under its original case name, so exports stay
  byte-stable and a newer build reads the real event back out. Tolerance triggers on *any* decode
  failure, not an allowlist — an allowlist is a second place to update and would silently degrade a
  brand-new event on the very build that writes it.
- **Retention never decapitates a trace.** Above `maximumStoredSteps` (10,000), whole **completed**
  workflows are dropped oldest-first by correlation group, never by row — pruning rows would make
  `steps(forCorrelationID:)` read as though a workflow began midway. Blocked, failed, escalated, and
  still-running traces are never dropped, and `unknown` never counts as a completion.
- **The cap is therefore soft**, and "over cap with nothing droppable" is a steady state. The O(rows)
  sweep backs off after an unproductive pass (`unprunableFloor` + `pruneRetryGrowth = 256`), bounding
  amortized cost to O(rows/256) per write; a step that completes a workflow clears the backoff at
  once. Under-cap writes are a single `fetchCount` that never materializes a row.
- **Privacy reset reaches it.** `RuntimeHost.resetAllHistory()` clears worklogs, sessions, execution
  records, performance events, event history, and artifacts, wired as the `operatorRuntimeHistory`
  phase of `PrivacyResetService` and resolved through `RuntimeAssembly.sharedHost` so rows from earlier
  launches are reached even if Mission Control was never opened.

**Proof.** `WorklogUnknownEventToleranceTests` (with a round-trip case guarding the `KnownWorklogEvent`
mirror against drift), `WorklogHealthTests`, `WorklogExportTests` in RuntimeCore;
`OperatorRuntimeStorageTests` for retention.

**Limits.** Genuine corruption is no longer distinguishable from a version downgrade at the type
level — keeping the bytes is the better trade either way. `RoutinePhase` deliberately gained no
`unrecognized` case, so derivations keep their exhaustive-switch guarantee; a newer phase is handled a
level up as `unknown("routinePhase", …)`. Installed playbooks survive privacy reset by design: the
catalog is configuration, not a record of activity. Retention for playbook/performance/execution
history is still an open decision.

## 8. Deterministic Check Registry

**What.** Mechanical, evidence-producing preconditions that run before the Judge. Three sets register
onto one registry:

| Set | Checks |
|---|---|
| Standard (`RuntimeCore/Checks/StandardChecks`) | `address.format`, `ens.format`, `chain.inScope`, `context.fresh` |
| Policy tool (`RuntimeKit/PolicyToolChecks`) | `policy.payload.valid`, `policy.chain.allowed`, `policy.approval.bounded`, `policy.address.checksum` |
| Record schema (`RuntimeKit/SchemaChecks`) | `receipt.schema`, `artifact.schema` |

**Invariants.**
- **Results are three-way, not boolean.** `DeterministicCheckSeverity` is `pass` / `warning` /
  `failure`. Only `failure` blocks. The warning tier — e.g. a well-formed but unchecksummed address —
  is a value callers branch on, reaches the approver in the escalation prompt, and renders as a warning
  in Mission Control rather than a green checkmark. `passed` is *derived* from severity so the two
  cannot disagree in a persisted record, and the encoded shape carries both keys so entries written
  either side of that change still read.
- **`context.fresh` is required by every production tool.** Freshness is not opt-in.
- **Chain references resolve through one type.** Friendly alias, `Chain` raw value, CAIP-2, decimal,
  and hex all go through `ChainScopeReference`, and `chain.inScope` / `policy.chain.allowed` share one
  scope (`StandardCheckConfiguration.allowedChains`) so they cannot admit different chain sets for the
  same capability. The payload check still refuses non-numeric aliases — its `chainID` is an EIP-155
  field, the one intentional difference, pinned by test.
- **Address validation means EIP-55**, not just hex shape (`AuralisEthereumAddress.checksumState(of:)`),
  so it is not a duplicate of `ToolSchemaField.Kind.address`.
- **Record shapes are versioned facts.** `ReceiptSchema` / `ArtifactSchema` plus persisted, optional
  `schemaVersion` columns, so legacy rows read as the shape they were written under and export
  `recordsHash` stays stable.

**Proof.** RuntimeCore's `StandardChecksTests.swift` (the "Standard deterministic checks" and "Chain
scope references" suites) and `DeterministicCheckSeverityTests`; RuntimeKit's
`ChainScopeAgreementTests`, `RecordSchemaCheckTests`, and `PolicyAddressChecksumCheckTests`. Coverage is
derived from `registeredCheckIDs` rather than a hand-written list, so a check cannot be registered and
then quietly never run.

**Limits.** ENS validation is a conservative subset of ENSIP-15, not the full spec: multi-label
subdomains are accepted, non-ASCII labels are refused, and homoglyph names fail closed. Chain scope and
the freshness window are host-injectable via `StandardCheckConfiguration` — that is a seam, so review
what a host injects.

## 9. Outcome Specs & Evaluation

**What.** An `OutcomeSpec` declares what success means for a goal, workflow, or playbook. It carries
two things that are deliberately not collapsed into one:

- `criteria: [SuccessCriterion]` — machine-checkable, each case decidable from `WorkflowStepLog` alone:
  `producedArtifact`, `completedWithin(seconds:)`, `noBlockedSteps`, `noFailedSteps`,
  `allDeterministicChecksPassed`, `judgeDidNotEscalate`, `reachedRoutinePhase(_:)`, `traceFullyLegible`.
- `proseCriteria: [String]` — authored intent that is descriptive and **never graded**.

`EvalCore.TraceEvaluator` grades a spec against a trace; `RuntimeHost.evaluateCompletedRun` calls it
once per finished workflow. `PerformanceRecord` (`RuntimeCore/Eval/`) stays the small portable summary
at the runtime boundary, alongside the richer `EvalCore.EvalResult` and
`PerformanceCore.PerformanceEvent`.

**Where.** `RuntimeCore/Eval/`, `EvalCore`, consumed by `PlaybookCore.Playbook.outcome`.

**Invariants.**
- **Grading reads the durable trace**, not an in-memory accumulation, so the grade rests on exactly the
  evidence a person auditing later would see — a step that failed to persist shows up as the same gap,
  not a rosier version.
- **An absent spec is a real answer.** No criteria means ungraded ("nobody said what success meant
  here"), never a pass and never a failure.
- **Legacy prose is not converted into criteria.** Inferring a criterion from a sentence would
  fabricate an expectation the author never declared and then grade real runs against it; a spec
  written before `criteria` existed decodes with none and reports inconclusive.
- **Evaluation is advisory and approval-gated.** `EvalCore` derives deterministic, evidence-linked
  recommendations with a persisted human lifecycle (proposed → accepted/rejected → applied). Handling a
  recommendation must never widen authority, mutate policy, grant capabilities, or edit playbooks, and
  every human transition emits a worklog entry and a receipt.

**Proof.** `TraceEvaluatorTests` and `OutcomeSpecSerializationTests` (EvalCore),
`EvalWiringTests` (RuntimeKit) covering the not-graded-without-a-spec and degraded-worklog paths,
`OutcomeSpecTests` (RuntimeCore).

**Limits.** Criteria are decidable from the worklog only — an outcome that depends on facts the trace
does not record cannot be expressed as a `SuccessCriterion` and belongs in prose. Rubric judging
(`RubricJudging`) is an optional opinion layer, not a gate. Evaluation informs decisions; it never
grants authority.

---

## Adjacent kernel contracts

Not among the nine, but part of the same substrate and assumed by them.

### Receipts & tamper-evidence

`ReceiptRecord` is hash-chained (`payloadHash` / `prev` / `chainHash`) and signed by a P-256
`ReceiptSigner`, with chain heads held in the Keychain per account. `ReceiptSignerFactory` persists
the key — a Secure Enclave blob where available, otherwise a stable software P-256 key.

Two invariants worth restating because they are easy to get wrong:

- **Integrity is a local claim.** Receipts are tamper-*evident* on the same device. Externally
  enforceable proof requires trusted infrastructure or signed receipt-head sync.
- **Export verification must pin `provenanceTrustAnchor()` through a channel separate from the
  exported JSON.** A fingerprint embedded in an export is never its own trust proof. Local and
  exported verification bind every receipt key to the trusted provenance identity, which is what makes
  a validly-signed but substituted signer pair fail.

The Secure Enclave *hardware* path is code-complete but simulator-unverifiable
(`SecureEnclave.isAvailable == false`), so CI exercises the software fallback. Tracked as L-03 in
`plans/Phase-1-Known-Limitations.md`.

### Agent sessions

`AgentSession` (`RuntimeCore/Session/`) groups a correlated run for the operator's benefit: actor,
authority, state, and the steps that belong to it. `GovernedToolPipeline` opens one lazily per
correlation ID, so sessions describe real work rather than being separately bookkept. Sessions are
cleared by `RuntimeHost.resetAllHistory()`.

### Capability leases

`CapabilityLease` / `CapabilityLeaseRegistry` (`RuntimeCore/Capability/`) are the `lease` half of
`AuthorityRef`: scoped, time-bounded, revocable grants surfaced in Mission Control's Powers section.
The pipeline resolves a lease per proposal and publishes expiry, so an expired lease is visible rather
than merely inert. `CapabilityImpactMapping` ties a capability to the impact class it can authorize.

### Model routing

`ModelRouting` chooses a `ModelRoute`; `ModelInferring` performs routed provider inference. These are
two responsibilities and must stay separate — see the AGENTS.md convention on not stamping
remote/provider telemetry unless the provider seam actually ran. `InferenceProvenance` +
`privacyImpact` and `InferenceTelemetry` carry the result into receipts as an AI Provenance section.
Readiness and open telemetry items live in `audits/Agent-Visibility-Readiness.md`.

### Package boundaries

ADR-008 is authoritative. Enforced by tests, not convention: the first-party graph must stay acyclic,
packages must not be empty identity stubs, retired stubs must stay absent, layer direction must hold,
and app-target package imports must be declared explicitly in Xcode.

### Adversarial coverage

RuntimeCore carries a firewall suite, plus an end-to-end malicious `GoalPlanning` double proving that
planner output cannot escalate into wallet signing. The `AutopilotCore` suite is a dedicated CI gate
for the same reason: the planner is untrusted input to the governed runtime, not a privileged caller.

---

## Verifying the kernel

Package tests are the fast, reliable route. `swift test` needs the Xcode-beta toolchain on this
machine (the CLT toolchain lacks `Testing.framework`):

```sh
export DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer
(cd RuntimeCore  && swift test)   # the eight kernel primitives
(cd EvalCore     && swift test)   # outcome grading
(cd TrustedUIKit && swift test)   # trusted request → component mapping
```

`ArchitectureBoundaryTests` lives in the app target (`AuralisTests`) because it reasons about the
whole package graph and the app's own sources; run it with the app scheme.

Last full verification — **2026-09-06**: RuntimeCore 247 tests / 35 suites, EvalCore 35 / 4,
TrustedUIKit 13 / 3, all passing.

## Adding to the kernel — checklist

1. **New tool** — declare impact honestly, list `requiredCheckIDs` (including `context.fresh`), set
   `requiresReceipt` for anything non-`readOnly`, register in a catalog reached by `bootstrap()`.
2. **New check** — pick an unused ID (bootstrap `precondition`s on conflicts), return a severity rather
   than a bare bool, and make the detail string useful to an approver reading it in an escalation.
3. **New event consumer** — if it is audit-critical, use `reliableEvents(...)` and surface subscriber
   health in Mission Control. If it is UI, use `events()`.
4. **New context source** — declare a contract with explicit missing/additional-field behavior; pass
   sensitive values as `.sensitiveReference`.
5. **New recorded act** — attribution is a compile error to omit, so supply the real actor, the real
   authority, and the correlation ID of the enclosing workflow. Never `ActorRef.system`.
6. **New agent-facing UI** — add a `TrustedUIRequest` case and its registry route together, or you will
   fail `trustedUIRequestsHaveProductionRoutes`.
7. **New playbook** — give it an `OutcomeSpec` with real criteria, or accept that its runs read as
   ungraded.
