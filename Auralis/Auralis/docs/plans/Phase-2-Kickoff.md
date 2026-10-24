# Phase 2 — Kickoff & Readiness

**Created 2026-08-17. Last reconciled 2026-10-22.** Phase 1 (Mission Control operator console) is
feature-complete in code; physical-device QA and App Review signoff remain open. Phase 2 foundations and selected
bounded capabilities have already advanced in the repository, so this is now a readiness and scope record rather than
an unstarted implementation plan. Its safety gates still govern what may be claimed or released.

**2026-09-07 revision:** the P2-EVAL scope below was overstated. `OutcomeSpec` evaluation is no longer
absent — `EvalCore.TraceEvaluator` grades declared criteria and `RuntimeHost.evaluateCompletedRun`
calls it on every finished run, with results persisted in production. What is actually left for
P2-EVAL is narrower and is now stated precisely. Kernel contracts moved to
`../reference/Runtime-Kernel.md`.

Companion docs: `../reference/Runtime-Kernel.md` (kernel contracts, as built),
`OperatorConsole-Ship-Readiness.md`
(residual punch list), `Phase-1-Physical-Device-QA-Suite.md`, `Phase-1-App-Review-Checklist.md`,
`Phase-1-Known-Limitations.md`, `ADR-008` (package boundaries), `ADR-010` (crypto-scoped Observe),
and the Social v1 release-gate set: `Social-v1-Relay-Readiness.md`,
`Social-v1-Abuse-and-Reliability.md`, and `Social-v1-Physical-Device-QA-Suite.md`.

---

## Entry criteria (Phase 1 → Phase 2 gate)

The original rule was that Phase 2 build-out would start only once the Phase 1 gate closed. Implementation work has
proceeded behind bounded, governed seams, but Phase 2 must not be treated as production-ready—and authority must not be
widened—until these non-compilation gates close:

- [ ] Physical-device QA suite passes with a **go** (`Phase-1-Physical-Device-QA-Suite.md`,
      MC-Device-001..013), especially the two ship blockers:
  - [ ] **MC-Device-010** BGTaskScheduler background firing on hardware.
  - [ ] **MC-Device-011** Secure Enclave receipt signing on hardware.
- [ ] `Phase-1-App-Review-Checklist.md` worked to a **go**; no undisclosed `Blocker`/`Major`.
- [ ] `Phase-1-Known-Limitations.md` reconciled — every open finding resolved or disclosed.

Rationale: Phase 2 grants agents *more* autonomy. We do not widen authority before the governance,
receipt-chain, and kill-switch guarantees are verified in the hand.

## What already exists

- **`PlannerCore`** — goal → `Plan` of `PlanStep`s. Deterministic (`DeterministicGoalPlanner`,
  `PlanTemplateCatalog`) and model-backed (`ModelGoalPlanner`) planners; `SequentialPlanOrchestrator`
  drives execution and consults a `StepAuthorizing` decision per step.
- **`AutopilotCore`** — the authority ladder for plans. `AutopilotAuthorizer` maps each step to
  `autopilot` / `needsConfirmation` / `blocked` by composing the app's **existing** `PolicyCore` +
  `CryptoMode`; a `TrustedRoutineAllowlist` only removes a per-run confirmation tap and **never** bypasses
  the policy gate. `AutopilotRunner` wires planner + authorizer + executor into one `run(_:)`.
- **`EvalCore` outcome grading + advisory recommendations** — more than groundwork now, and worth
  stating precisely so P2-EVAL is not rebuilt:
  - **Grading exists and runs.** `OutcomeSpec` carries `[SuccessCriterion]` (8 machine-checkable cases,
    each decidable from the worklog alone); `TraceEvaluator` grades a playbook's declared criteria
    against the durable trace; `RuntimeHost.evaluateCompletedRun` calls it once per finished run and
    records an `EvalResult`. Production persists those via `SwiftDataEvalResultStore`
    (`PersistentRuntimeHost`); a playbook with no criteria reads as *ungraded*, never as a pass.
  - **Advisory recommendations exist.** `ImprovementRecommendationEngine` derives deterministic,
    evidence-linked recommendations from `OperatorReportCard`s with a persisted human lifecycle
    (proposed, accepted, rejected, applied). They cannot edit playbooks, mutate policy, grant
    capabilities, or widen authority.
  - **Not enabled:** rubric judging. `RubricJudging` exists, but `PersistentRuntimeHost` does not inject
    a judge, so production runs `NoRubricJudge()`, which always returns `nil`. Model-scored opinions on
    a trace are wired but off.
- **`SocialCore`** — SharedSession + collaborative approvals + Ritual catalog/store/engine. Originally
  Phase 2 scope (P1-SOCIAL-101/102), pulled forward and wired in Phase 1: Mission Control can create
  sessions, add local participants, share receipts/artifacts/workflows, open collaborative approvals,
  vote them through the normal approval resolver, and run collaborative rituals that create shared
  sessions. The persisted social state participates in privacy reset.

`PlannerCore` and `AutopilotCore` remain bounded POC/infrastructure, although the governed runner is wired to
an explicit user-triggered goal surface: **`MissionControlRunGoalView`**, reachable as the console's
"Run a Goal" section, calling through `RuntimeHost` + `AutopilotStepExecutor`. Neither package is
imported by the app target directly — the app reaches them through `RuntimeKit` and
`MissionControlFeature`, per ADR-008. `RuntimeKit`'s `AutopilotGoalWiringTests` pins the behaviour that
matters (deliberation steps produce receipts and telemetry; deliberation and the governed step share one
trace); verified green 2026-09-07. This is still not unattended production autonomy — and note that
on-device inference fails on the simulator, so autopilot falls back to templates there and real
telemetry needs hardware. `SocialCore` is
code-wired for the bounded human-coordination primitives above. The Social relay path is now enabled in Debug and
Release, but that configuration is not production-readiness evidence: relay terms/quotas/retention/SLA and two-device
QA remain open, and peers cannot yet carry independently verifiable wallet proof, so remote binding votes and queue
mutations fail closed. Full Social v1 remains a separate production-public effort tracked in the Social readiness set.
None of these
pieces increase authority beyond what the Phase 1 policy substrate already grants.

## Phase 2 scope

Proposed epic order, each an increment on the proven console:

| Epic | Current status | Phase 2 scope | Builds on |
|---|---|---|---|
| P2-EVAL | **Grading shipped**; three specific gaps remain | Not "build evaluation" — that exists (see above). What remains: (1) **enable rubric judging** in production, or decide deliberately not to and delete the seam; (2) **criteria beyond the worklog** — an outcome that depends on facts the trace does not record cannot currently be expressed as a `SuccessCriterion` and falls back to ungraded prose; (3) **make evaluation decision-informing** — today `EvalResult` and performance history are read by humans in Mission Control and by the advisory engine, but nothing consumes them to influence routing, scheduling, or step authorization. Still descriptive of authority, never authority-granting. | `PerformanceCore`, `EvalCore` grading + advisory lifecycle |
| P2-AUTOPILOT | Integrated governed POC; production deferred | Promote the explicit user-triggered `PlannerCore`/`AutopilotCore` runner to production **governed autopilot**: unattended `observe`/`assist` steps, confirmation-gated `execute`, trusted-routine allowlist management UI, and device verification. | `PlannerCore`, `AutopilotCore`, Approvals/Powers |
| P2-SCHED | Bounded foundation; advanced behavior absent | **Advanced scheduling** beyond the bounded skeleton — richer triggers, windows, backoff, dependency-aware runs. | `SchedulingCore`, `RuntimeBackgroundScheduler` |
| P2-PACKS | Extension surface absent; attribution vocabulary exists | **Third-party operator packs** — a signed, capability-scoped extension surface for operators beyond the built-in three. Note that `ReceiptActorDetail.operatorPack(_:)` already exists and is used (e.g. `music.operator`), so the *attribution* vocabulary is there; what is missing is loading, signing, and sandboxing. Per ADR-008, hostile native pack code needs XPC or an Enhanced Security extension first — in-process capability isolation is not a sandbox. | `OperatorsFeature`, `CapabilityLease` |
| P2-MULTI | Human/session foundations; autonomous orchestration absent | **Multi-agent orchestration** — multiple cooperating agents under one worklog/receipt chain, with `SocialCore` shared sessions. | `SocialCore`, `RuntimeCore` worklog/events |
| P2-BUDGET | Absent | **Stablecoin budgets / x402 + agent mandates** — bounded spend authority with hard, receipted limits. Gated hardest; strictly behind Operate + explicit mandate. | `PolicyCore`, `CryptoMode`, receipt chain |
| P2-IMPROVE | Advisory lifecycle only; automatic loop absent | **Self-improvement loops** — evaluation-driven playbook refinement, still human-approved and fully receipted. | P2-EVAL, PlaybookCore |
| P2-MEMORY | Absent; explicitly deferred | **Advanced memory graphs** — a separately specified agent-memory graph only if concrete product needs justify it. Ordinary persisted media, social, session, and worklog graphs do not satisfy or imply this scope. | `RuntimeCore` sessions/events, future design |

## Guardrails carried over (non-negotiable, unchanged from Phase 1)

- **Governance is never bypassed.** Every executing step routes through the same
  `GovernedToolPipeline` / `PolicyActionGating`. Trust and performance history remove *taps*, never
  *gates*.
- **Crypto Observe boundary holds (ADR-010).** Observe blocks wallet-affecting steps with a denial
  receipt; Assist escalates for approval; Operate proceeds only when policy **and** routine trust allow.
- **Everything is receipted.** New autonomy produces the same tamper-evident, signed receipt chain and
  appears in Mission Control (Timeline / Sessions / Receipts / Performance).
- **Kill switch is absolute.** The global pause must short-circuit any Phase 2 automation to recorded
  no-ops, same as Phase 1 routines.
- **Package boundaries per ADR-008.** New capability lives in its own package; the app composes.

## Current next steps

1. Close the Phase 1 device/review gate and record the real-device evidence before making a production-readiness claim.
2. Keep durable governed-runtime contracts in `../reference/Runtime-Kernel.md`; do not recreate the retired monolithic
   phase implementation plan.
3. Close the remaining P2-EVAL gaps deliberately, then advance unattended automation only behind confirmation,
   capability, policy, kill-switch, and receipt guarantees.
4. Add a Phase 2 physical-device QA suite before shipping unattended runs.
5. Keep Social public claims blocked until its readiness evidence, portable peer proof, and two-device suite close.
