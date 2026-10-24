# Agent Visibility (P1-AGENT-101/102/103) — Readiness & Open Items

Status snapshot for the three "Agent Visibility" features in Mission Control. Records what was
verified, what was fixed, and the items still requiring validation before shipping.

Last reviewed: 2026-08-20.

## Feature status

| Feature | Status | Notes |
| --- | --- | --- |
| P1-AGENT-101 Agent Activity Timeline | Implemented, end-to-end wired | Deliberation (considered/rejected + rationale), checks, judge decision, executed duration, token/model/locality, estimated cost. See item 1 for the device caveat. |
| P1-AGENT-102 Context Bundle Inspector | Implemented | Full bundle: accounts/chains in scope, memory, provenance, permissions, model used, inference locality, capability/receipt/artifact counts, contract validation. |
| P1-AGENT-103 Proposal Diff Viewer | Implemented + real transaction simulation | Declared-impact diff **plus** on-chain dry-run (see "Resolved" below). |

## Resolved — Local-First AI visibility gaps (P1-AI-101/102, 2026-08-20)

Three gaps found in the "is this shippable" audit of the Local-First AI category are now closed:

- **Model routing is a real router, not just a seam (P1-AI-101).** Added
  `RuntimeCore.TaskKindModelRouter`: a provider-agnostic table (task-kind → `ModelRoute`) with an
  ordered fallback chain (`fallback` router → `defaultRoute`). Operators now carry task kinds instead
  of route literals, `OperatorExecutor` resolves the route at execution time, autopilot resolves
  `ModelTaskKind.autopilotStep`, and search resolves `ModelTaskKind.searchAssistant` before starting
  Foundation Models. The `fallback` slot is the explicit future-provider / DViances-agent hook.
- **`privacyImpact` is first-class and locality-derived (P1-AI-102).**
  `InferenceLocality.privacyImpact` / `.privacyImpactShort` (mirrored on `InferenceProvenance` and
  `ModelRoute`) turn local/remote into the trust-facing "inputs stay on this device" / "inputs leave
  this device" framing. New operator/autopilot receipts stamp `privacyImpact`; older receipts still
  synthesize the row from `inferenceLocality`, so the display cannot drift from the recorded locality.
- **Every receipt now surfaces inference provenance, not just agent sessions (P1-AI-102/103).** The
  shared `ReceiptsCore` presentation has an **AI Provenance** section for `modelProvider`, `modelClass`,
  `inferenceLocality`, `privacyImpact`, prompt/completion tokens, `tokensEstimated`, `durationSeconds`,
  and `estimatedCost`. Mission Control also shows privacy impact and execution time in session detail,
  and the Context Bundle contract requires `inference.privacyImpact` and `inference.executionTime` from
  `OperatorExecutor`.

Coverage: `RuntimeCoreTests` (`TaskKindModelRouter` suite + `localityDerivesPrivacyImpact`),
`OperatorsFeatureTests` (injected model router output), `RuntimeKitTests` (autopilot receipt telemetry),
`MissionControlFeatureTests` (session/context aggregation), and `ReceiptsCoreTests` (AI Provenance
presentation). All green.

## Resolved — Provider composition root + model-hop telemetry (P1-AI-101/103, 2026-08-20)

Two gaps from the "is Local-First AI shippable" audit are now closed:

- **A single provider composition root, not per-call-site defaults (P1-AI-101).** New
  `RuntimeCore.ModelProviderRegistry` is the one place providers are declared as data — each
  contributes its task-kind routes and (for non-call-site backends) a `ModelInferring` client. It vends
  a composed `makeRouter()` (registered providers layered over the canonical
  `TaskKindModelRouter.localFirstDefault`, then the guaranteed default floor) and a composed
  `makeInferenceClient()` (`RoutingInferenceClient`, dispatching by route id and failing closed for
  unregistered routes). The app's `ModelProviderComposition` builds it once and threads the two
  protocols into `RuntimeHost` (operators + autopilot) and the search assistant, so bringing a remote
  API provider or a future DViances agent online is one `register(...)` call — no feature call site
  changes. With nothing registered the behaviour is identical to the previous local-first defaults.
- **"Model hops" is a real invocation counter (P1-AI-103).** `AgentSession.modelHops` counts every
  handoff to an inference backend (distinct from `modelsUsed.count`: one model called three times is
  one model, three hops), incremented on each `note(model:)`/`note(telemetry:)`. Persisted sessions
  decode tolerantly (legacy blobs → 0 hops). Mission Control's `InferenceSnapshot.modelHops` reconciles
  the session counter with telemetry-bearing receipts via `max(...)` so operator runs (which stamp
  receipts without touching the session counter) aren't undercounted, and the session detail now shows
  a correct "Model hops" row (previously mislabelled `modelCount`, the distinct-model count, now its
  own "Models used" row).

Coverage: `RuntimeCoreTests` (`ModelProviderRegistry` suite: local-first default, provider override
precedence, client dispatch + fail-closed; `AgentSession` hop counting + legacy decode) and
`MissionControlFeatureTests` (`InferenceSnapshot model hops`: per-receipt count, session/receipt
reconcile, not-recorded). App `BuildProject` green; `RuntimeCore` 69, `RuntimeKit` 21,
`OperatorRuntimeStorage` 9 tests pass.

## Resolved — Data reads no longer masquerade as AI inference (P1-AI-102/103, 2026-08-20)

Audit gap: a deterministic local data operator (the on-chain ledger indexer, `usesInference == false`)
still emitted an `InferenceTelemetry` carrying its route provenance. Because that telemetry stamped a
non-empty `modelProvider`/`inferenceLocality` on its receipt and a `note(telemetry:)` on its session,
Mission Control counted the ledger read as a **model hop** and folded it into the AI telemetry
aggregate, and the receipt rendered an **AI Provenance** section — blurring "local data read" with
"a model ran", which undercuts the trust feature. It was a live defect in the local-first build (fired
on every on-chain-watch run), not just a latent remote-provider path.

Fix: `InferenceTelemetry` gained an explicit `usesInference` flag (the source of truth about whether a
model actually ran), serialized in both its `Codable` form and its `outputFields` round-trip, defaulting
to `true` so legacy receipts/sessions keep their prior behaviour. Every trust surface now gates on it:

- `OperatorArtifactComposer.telemetry` stamps `usesInference: false` for data reads (still records the
  route + wall-clock duration for provenance, but flagged as non-inference).
- `AgentSession.note(telemetry:)` ignores non-inference telemetry, so a data read never increments
  `modelHops` or the models-used list.
- `MissionControlHomeModel.inferenceSnapshot` skips receipts flagged non-inference — no hop, no
  provider/locality leakage into the AI aggregate. Legacy receipts (no flag) are unchanged.
- `ReceiptContentPresenter.categorizedRows` keeps a data read's provenance visible but out of the AI
  Provenance section and synthesizes no privacy-impact row; the internal `usesInference` key is never
  rendered.

Coverage: `RuntimeCoreTests` (`nonInferenceTelemetryDoesNotCountAsHop`,
`usesInferenceSurvivesOutputFieldsRoundTrip`), `MissionControlFeatureTests`
(`dataReadReceiptIsNotCountedAsModelHop`, `dataReadDoesNotDiluteRealInferenceHops`). App `BuildProject`
green; `RuntimeCore` 71, `ReceiptsCore` 17, `OperatorsFeature` 7, `MissionControlFeature` 61 tests pass.

## Resolved — Transaction simulation (was the P1-AGENT-103 gap)

The diff viewer previously showed only a declared-impact before/after (capability, boundary, receipt,
checks, data accessed) — no on-chain dry-run. It now performs a real simulation:

- `ProposalSimulating` protocol + `ProposalSimulation` / `ProposalAssetChange` result types, and an
  `EVMTransactionIntent` extractor (`MissionControlFeature/Sources/MissionControlFeature/ProposalSimulation.swift`).
- `AlchemyProposalSimulator` (app target, `Auralis/Aura/WalletConnection/AlchemyProposalSimulator.swift`)
  calls Alchemy `alchemy_simulateAssetChanges` and surfaces revert status, gas used, and predicted
  balance/asset deltas. Routed through the existing `ProviderConfigurationResolving` seam.
- `MissionControlHomeModel.simulateProposal(_:)` + per-proposal state; rendered in a "Transaction
  simulation" section in `MissionControlProposalDetailView`.
- Degrades gracefully: `notApplicable` for non-transaction proposals, `unavailable` when no key /
  endpoint / network. Unit tests cover the not-applicable, unavailable, injected-result, and intent
  extraction paths.

## Resolved — Simulator trust-surface hardening (2026-08-19)

Three follow-up fixes to the P1-AGENT-103 simulator, so predicted movements and defaults never read
as misleading facts:

- **Direction is never guessed.** `ProposalAssetChange.Direction` gained an `.unknown` case;
  `AlchemyProposalSimulator.mapChange` returns `.unknown` (neutral glyph, no +/− sign) when the
  proposal carries no sender address, instead of defaulting to `.outgoing`.
- **Assumed network is labelled.** `ProposalSimulation.chainAssumed` is set when a proposal omits its
  chain and the simulator falls back to Ethereum mainnet; the detail view shows an "Assumed — the
  proposal didn't specify a network" note under Network.
- **Gas cost estimate.** `ProposalSimulation.estimatedGasCostEth` — a best-effort `eth_gasPrice` ×
  `gasUsed` estimate rendered as "~<x> ETH". Non-fatal: a failed price fetch just omits the line.
- Coverage: `AuralisTests/AlchemyProposalSimulatorTests.swift` (7 tests, all passing) for the
  direction mapping (unknown/incoming/outgoing/dropped) and `formatEth` output.

## Resolved — Durable trust record for approvals (2026-08-19)

The diff and on-chain simulation an operator approved against were previously ephemeral (computed
`proposalDiffRows` + an in-memory `proposalSimulations` dict), so the approval receipt recorded the
decision but not *what was shown* at decision time. `MissionControlHomeModel.resolve(_:decision:)` now
persists both into the approval receipt payload:

- `proposalDiff` — the declared-impact diff, row-for-row (`label`/`before`/`after`/`risk`).
- `simulation` — present only when a dry-run had run: `status`, `chain`, `gasUsed`,
  `estimatedGasCostEth`, and predicted `assetChanges` (direction/amount/symbol/counterparty).

So "what was I looking at when I approved this?" is reconstructable from the durable, exportable audit
trail. Covered by `approvalReceiptPersistsDiffAndSimulationSnapshot` and
`approvalReceiptOmitsSimulationWhenNoneRan`.

## Resolved — Context contract covers the trust-critical provenance fields (2026-08-19)

`inspectedContextContract` previously asserted only `operator.mode` + three counts. It now also
requires `model.used`, `inference.locality`, and `permissions.granted` to come from their
authoritative source (`OperatorExecutor` / `CapabilityLeaseRegistry`) with the `derived` data class —
so a misattributed value on the sovereignty surface fails validation, while the legitimate
"Not recorded" / "None granted" states still pass (those fields are always emitted).

## Resolved — Trust-surface consistency fixes (2026-08-19)

Three follow-up fixes found in a code audit of the shipped implementation:

- **Chains-in-scope now agrees with the simulator.** `contextChainsInScope` (P1-102) read only the
  `chain` parameter key, so a proposal specifying `chainId`/`network` showed "None in scope" while the
  simulator (P1-103) still resolved and dry-ran it. Both now go through
  `EVMTransactionIntent.chainKey(from:)`, which checks every alias (`chain`/`chainId`/`network`).
- **Large transfer values no longer simulate as zero.** `EVMTransactionIntent.normalizeHexQuantity`
  parsed a decimal wei value via `UInt64`; anything above ~18.4 ETH silently fell back to `0x0` and
  dry-ran as a safe zero-value transfer. Replaced with arbitrary-precision decimal→hex
  (`decimalStringToHexQuantity`) — no new dependency.
- **No redundant RPC per navigation.** `simulateProposal(_:)` now reuses a `.finished` result instead
  of re-hitting the endpoint each time the proposal detail reopens; a `force` flag allows an explicit
  re-run against fresh chain state.
- Coverage: `evmIntentPreservesValuesAboveUInt64`, `chainKeyResolvesAcrossAliases` in
  `MissionControlTests.swift`.

## Open item 1 — Model/token telemetry is only real on a physical device

**Risk:** P1-AGENT-101/102's token/model/local-vs-cloud fields are the most trust-critical numbers,
but on the simulator on-device FoundationModels inference fails (known beta `safety_guardrail`
behavior) and autopilot falls back to templates. In that path the telemetry reads `Not recorded` or
`~…(estimated)` rather than real usage.

**To validate before shipping:**
- Run a real autopilot goal on a **physical device** (inference must succeed, not fall back).
- Open Mission Control → Timeline → a completed session and confirm the Session detail shows a real
  `Model`, `Inference = On-device (local)`, non-estimated `Tokens`, and a plausible `Estimated cost`.
- Confirm the Context Bundle Inspector's `model.used` / `inference.locality` fields match.
- Confirm the `~…(estimated)` suffix appears only when telemetry is genuinely approximated.

## Resolved — Full build + test suite run green for this change set (2026-08-20)

Confirmed green on the beta toolchain after the P1-AI-101/102 changes above:
- App `BuildProject` — 0 errors.
- `RuntimeCore` `swift test -—disable-sandbox` — 63 tests / 16 suites (incl. `TaskKindModelRouter`, `localityDerivesPrivacyImpact`).
- `OperatorsFeature` `swift test --disable-sandbox` — 6 tests (incl. injected route telemetry output).
- `RuntimeKit` `swift test --disable-sandbox` — 19 tests (incl. `autopilotGoalRecordsDeliberationStepReceiptsAndTelemetry`).
- `MissionControlFeature` `swift test --disable-sandbox` — 56 logic tests; 21 AppKit snapshot tests skipped by their visual-lane gate.
- `ReceiptsCore` `swift test --disable-sandbox` — 17 tests (incl. the "Inference provenance presentation" suite).

## Manual QA checklist for the new simulation UI

- Proposal with a real `to`/`value` on a configured chain → shows success/revert, gas, and balance
  deltas.
- Proposal that reverts → red "Would revert" with the node's reason.
- Non-transaction proposal → "No on-chain transaction to simulate".
- No Alchemy key configured → "Simulation unavailable" with the configure-a-key explanation.
- Airplane mode → "unavailable", no crash, no spinner stuck.
