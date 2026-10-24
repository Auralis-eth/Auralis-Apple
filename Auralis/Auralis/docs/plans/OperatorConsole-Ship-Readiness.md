# Operator Console — Ship Readiness Checklist

**Current status (reconciled 2026-10-22):** The operator-runtime feature surface remains code-complete, but physical
device, App Review, and disclosure gates remain open. Historical test counts below are evidence from their stated dates,
not a claim that the current working tree has just been re-run. Social relay is enabled in Debug and Release even though
its external evidence, portable peer-proof, and two-device gates remain blocked.

Status of the operator-runtime / Mission Control program (runtime kernel + Phase 1). Everything below the
"Done" line was built and verified by the dated package/app runs recorded below. The "Remaining" section is the
honest set that still needs a device, real App Review, design/QA sign-off, or an explicit current-tree rerun.

## Ship blockers (as of 2026-08-17)

Phase 1's *feature surface* is code-complete and unit/snapshot-verified. It is **not** "100% ready to
ship." What stands between it and shipping is **device-only verification and an App Review pass** — none
of it closeable by compiling. The honest open set:

- ❌ **BGTaskScheduler background firing** — code + Info.plist done, but never verified on a physical
  device. See `Phase-1-Physical-Device-QA-Suite.md` → MC-Device-010.
- ❌ **Secure Enclave signing** — `SecureEnclaveReceiptSigner` implemented and wired via
  `ReceiptSignerFactory`, but the hardware path is unverified (`SecureEnclave.isAvailable == false` on
  the simulator). See MC-Device-011.
- ❌ **Physical-device QA sweep** — kill switch halting routines, approve/reject/defer, artifact export,
  receipt verify/export, privacy reset with the new stores. See `Phase-1-Physical-Device-QA-Suite.md`.
- ❌ **App Review checklist refresh / P0 known-limitations** — the Phase-1 checklist
  (`Phase-1-App-Review-Checklist.md`) and Known-Limitations (`Phase-1-Known-Limitations.md`) docs now
  exist and must be worked/signed off before submission.
- ⚠️ **Localization** — deferred by decision (English-only). Accepted, but a stated limitation, not
  "complete."

The automated companion gate is tracked in `P0-UI-Test-QA-Suite.md`; the manual device gate is
`Phase-1-Physical-Device-QA-Suite.md`.

> **Social v1 production gate (created 2026-08-21; reconciled 2026-10-22):**
> Public relay-backed Social v1 is **enabled in configuration but not release-ready**
> (`AURALIS_SOCIAL_RELAY_ENABLED = YES` in Debug and Release). Code-level
> completion and local abuse/reliability controls are implemented and package-tested (owner-only session
> authority, verified-author gating, per-topic rate limiting, fail-closed quarantine, random invite minting,
> governed-approval-only resolution), but the non-code gates remain open: WalletConnect/IRN relay
> terms/quotas/acceptable-use/retention/SLA (`Social-v1-Relay-Readiness.md` still Blocked) and the
> two-device physical QA. Portable peer wallet proof is also unimplemented: the local Boolean ownership result is not
> independently verifiable by another installation, so remote binding actions fail closed. App Review copy must
> avoid public-network, centralized-moderation, guaranteed-live-sync, and production-supported third-party
> wallet claims until those gates close.

> **Update 2026-08-20 (Category 2 "Multi-Agent Runtime" foundations — P1-RUNTIME-101/102/103 closure):**
> A follow-up implementation pass closed the remaining code gaps found in the runtime-foundation review.
> Approval decisions now append through `RuntimeHost.appendRuntimeReceipt(...)`, so approval receipts,
> `receiptCreated` events, session receipt linkage, approval IDs, and execution updates are one runtime
> operation. The Powers tab now has explicit lease/restriction authoring controls, not just inspection and
> revocation. App source is guarded against direct `ActionPolicyGate` / `PolicyActionGateService` bypasses.
> `SwiftDataRuntimeEventHistoryStore` no longer prunes at the arbitrary 500-event write cap; it now keeps
> the newest 10,000 events via the named `maximumStoredEvents` retention guard, while screens keep their
> smaller read limits.
> - **P1-RUNTIME-101 Runtime Event Bus:** `RuntimeEventBus` (multi-subscriber `AsyncStream` fan-out, no
>   Combine) + durable `SwiftDataRuntimeEventHistoryStore`. `WorkflowEvent` covers all seven listed
>   streams — planner (`plannerStarted/Completed/Failed`), policy (`policyDecision`), receipts
>   (`receiptCreated`), execution (`executionUpdate`/`workflowStarted`/`workflowBlocked`), context
>   (`contextRefreshed`), memory (`memoryTouched`), approval requests (`approvalRequired`) — plus lease
>   and session lifecycle. Surfaced in Mission Control Timeline/Activity.
> - **P1-RUNTIME-102 Agent Session Model:** `AgentSession` tracks start/end, goals, capabilities,
>   receipts, approvals, artifacts, models, prompt/completion tokens, cost, and memory touches; durable
>   `SwiftDataAgentSessionStore`; wired via `startSession`/`finishSessionIfTerminal`/`noteRuntimeSession`
>   in `RuntimeHost`.
> - **P1-RUNTIME-103 Capability Lease UI:** `CapabilityLease` (time-boxed, scoped, session-bound) +
>   `CapabilityRestriction` (the negative "No wallet access" / "No external network"); durable
>   `SwiftDataCapabilityLeaseStore`. `MissionControlCapabilitiesView` (the "Powers" tab) can now grant
>   temporary capabilities, create explicit denials, group active leases by scope, show reason + duration,
>   and offer per-row **Revoke** for leases and restrictions.
> - **Persistence fails closed:** `RuntimeHost.persistent(...)` backs sessions, event history, and leases
>   with SwiftData via `OperatorRuntimeStorage`; if the container can't be created the host starts paused
>   rather than silently going in-memory.
>
> **Residual ship blockers for these three (verification only, no known code defect):**
> - ❌ **Full test-suite/device verification for the runtime foundations** — code diagnostics and app build
>   should be green before shipping, then repeat the Mission Control device QA paths for approval,
>   lease grant/revoke, explicit denial, receipt/session history, and privacy reset.
> - ⚠️ **Scope caveat — the autopilot/planner layer these foundations feed is still POC** (`PlannerCore`
>   / `AutopilotCore`, commit `3d73024`); on-device inference falls back to templates on the simulator, so
>   real session telemetry (tokens/cost/model hops) needs a physical device. The Category-2 *substrate* is
>   done; the autonomous agents riding on it are not — consistent with Category 2 explicitly not requiring
>   true autonomous agents yet.

> **Update 2026-08-13 (EPIC P1-100 acceptance-criteria closure):**
> Closed the remaining code-level AC gaps in Mission Control Core so P1-101..104 are fully met:
> - **P1-102 Timeline states:** `WorkflowState` now has distinct **`queued`** and **`failed`** states
>   (previously `failed` collapsed into `blocked` and there was no `queued`). State is derived from the
>   durable worklog (`state(forWorklog:)`) — proposed-only = queued, `.failed` = failed — with the lossy
>   live-event path kept only as a fallback for workflows with no worklog yet.
> - **P1-102 Timeline filters:** added **account** and **playbook** filters (Pickers) alongside status +
>   ID search. Facets are derived per workflow — account from the proposal's `account`/`address`/`ens`
>   parameter (else "No account"), playbook from the proposal intent/toolID (else "Ad-hoc").
> - **P1-102 Timeline links:** the session detail now lists correlated **Receipts** and **Artifacts** as
>   `NavigationLink`s into their existing detail screens (was counts-only).
> - **P1-103 Activity Feed:** now **grouped by session** (correlation id), each event tagged with a
>   category chip (**observation / preparation / approval-needed / completed**), and rows **link out to
>   receipt detail** when a receipt resolves. `workflowStarted` promoted to high-signal so "observation"
>   is representable; `executionUpdate` stays filtered as noise.
> - **P1-101 Home:** added a **Freshness & context** section (contract status + per-field freshness) and
>   a **Revoke capabilities** section (inline revoke), so Home shows both stop *and* revoke controls plus
>   freshness/context status. Added **Queued** and **Failed** to the console counts.
> - **P1-104 Mode:** Observe / Assist / Operate are now three **distinct surface rows** with
>   Read-only / Approval-gated / Evidence-gated status and a plain-language "what it allows", not just
>   prose.
> - **Tests:** +4 logic tests (distinct states, account/playbook filters, activity grouping/category);
>   `durableWorklogHydratesTimeline` updated (bare proposal is now `queued`). Re-recorded 4 image
>   baselines (home, home-populated, mode, timeline). MissionControlFeature: **11 logic + 17 snapshots
>   green**; app `BuildProject` green.
> - **Superseded account-filter fixture:** this batch originally used a concrete sample account to prove
>   the account-filter path. Production defaults no longer contain that target: On-Chain Watch now
>   requires an explicit identity-scoped, chain-qualified address and UI fixtures provide test-only
>   data. The production adapter combines scoped receipt history with a bounded read-only balance
>   snapshot.

> **Update 2026-08-13 (Assist/Operate rollout cleanup):**
> - **Governed runtime receipts are mode-aware:** `ReceiptStoreSink` now stamps tool receipts from the
>   active `CryptoMode`, and routine receipts use the same mode mapping.
> - **Background runtime uses persisted mode:** `RuntimeBackgroundScheduler.runInBackground()` builds the
>   shared host with `ModeState` instead of falling back to the default Observe provider.
> - **Account + ENS receipts are mode-aware:** live account/gateway/shell/ENS assembly paths thread the
>   active mode into receipt recorders; test/default paths still fall back to Observe.
> - **Package policy gate is evidence-injectable:** `PolicyActionGateService` now accepts execution evidence
>   and signing-chain allowlists so package-level tests and fallback adapters do not silently deny every
>   high-risk Assist/Operate attempt. App source routes policy decisions through `PipelineBackedPolicyGate`.
> - **Docs and UI copy refreshed:** ADR-004/ADR-010 and runtime comments no longer describe the shipping app
>   as Observe-only; the profile policy panel now describes governed actions under the current mode.

> **Update 2026-08-13 (hardening batch — this pass):**
> - **Package tests re-verified green** with the Xcode-beta toolchain (`DEVELOPER_DIR` = Xcode-beta):
>   RuntimeCore 46, ArtifactCore 5, ArtifactStorage 4, PlaybookCore 4, PerformanceCore 3,
>   SchedulingCore 7, OperatorsFeature 3, SocialCore 9, OperatorRuntimeStorage 5, ReceiptStorage 7,
>   MissionControlFeature 4 unit + 17 image snapshots. App `BuildProject` green.
> - **Accessibility audit — DONE (code):** audited all 14 Mission Control sections. Fixes landed:
>   sidebar selection now exposes `.isSelected` to VoiceOver (was visual font-weight only); non-interactive
>   multi-`Text` rows combined into single VoiceOver elements (Home events+receipts, Activity, Receipt
>   timeline, Performance health+runs, Artifact version history, Routines text block). Dynamic Type is
>   satisfied by text styles throughout; contrast uses system semantic colors that are never the sole
>   status carrier (reviewed & accepted per iOS conventions). On-device VoiceOver/Dynamic-Type sweep is
>   the residual device check.
> - **Populated snapshot baselines — DONE:** added an injectable `referenceDate` clock to
>   `MissionControlHomeModel` (replaces the two inline `.now` in the context bundle) plus a
>   `relativeText(_:)` helper; Capabilities/Context relative rendering now uses it instead of the wall
>   clock. Added a `#if DEBUG seedForSnapshot(...)` seam and recorded 5 populated baselines (home,
>   receipts, capabilities, performance, context). 17/17 snapshots green.
> - **ReceiptStorage reset tests:** the old "fails in the bare `swift test` sandbox" note is **stale** —
>   the reset tests already inject `InMemoryReceiptIntegrityHeadStore` and `ReceiptPersistenceStore`
>   defaults to `DefaultReceiptSigner()` (software, no Keychain); the only throwing Keychain type is not
>   exercised by any test. 7/7 pass. Removed from the open list below.
> - **Localization decision:** deferred (wiring + translations) to a single future pass using WWDC
>   on-device/AI translation across **all** packages — the app is English-only everywhere else, so
>   half-localizing one package would be misleading. English ships fine today.
> - **BGTask + Secure-Enclave:** code paths re-verified (see the device-steps section at the bottom).

> **Update 2026-08-12 (code-completion batch):**
> - **Secure-Enclave signing (code):** `SecureEnclaveReceiptSigner` (CryptoKit SE P-256) added to
>   RuntimeCore; `ReceiptSignerFactory` (ReceiptStorage) persists the signing key in the Keychain
>   (Enclave blob when available, else a stable software P-256 key) and is wired into
>   `ReceiptStores.live`. Signatures now use a **stable identity across launches** instead of an
>   ephemeral per-launch key. The SE-hardware path still needs a device to verify.
> - **BGTask (code):** confirmed complete — `.backgroundTask(.appRefresh(...))` + Info.plist identifier
>   + launch-time reschedule + handler → `runDueRoutines`. Device firing remains.
> - **P1-SOCIAL-101/102:** built as `SocialCore` and code-wired through Mission Control: shared sessions
>   persist locally, privacy reset clears them, participants/context/workflows can be added, collaborative
>   approvals store the full request snapshot and resolve through the normal approval path, and
>   collaborative rituals open sessions and file produced artifacts. App build-for-testing is green; the
>   targeted app privacy-reset test passes. Standalone package tests were blocked in this sandbox by
>   SwiftPM manifest sandboxing, so package execution should be rerun in a normal developer shell.
> - **Snapshot baselines:** infra now exists — `swift-snapshot-testing` added to
>   `MissionControlFeature` tests; `MissionControlSnapshotTests` records + verifies empty-state
>   baselines for all 12 sections (12/12 green on host). Populated-state + on-device parity are the
>   remaining follow-ups.

## Done & verified (compile + unit)
- **Kernel:** all nine runtime primitives plus the adjacent receipt-chain, lease, session, and
  adversarial contracts. Documented in `../reference/Runtime-Kernel.md`; not restated here. Verified
  2026-09-06 — RuntimeCore 247 tests / 35 suites, EvalCore 35/4, TrustedUIKit 13/3, all green.
  Crypto-scoped `DomainJudge` per ADR-010; `PauseGate` kill switch.
- **Trusted UI adoption in the console (2026-08-17):** the registry contract lives in
  `../reference/Runtime-Kernel.md` §Trusted UI Requests; what is console-specific is that MC now
  *renders through* it — proposal detail (ApprovalSheet incl. defer + RiskBanner), approvals-row
  RiskBanner, Capabilities PermissionCard, Receipts ReceiptCard, and Context redaction (`.sensitive`
  never shown raw). Bespoke inspector chrome (nav/filters/a11y IDs) intentionally kept — a superset of
  the generic components. Affected snapshot baselines re-record in the simulator visual lane (host
  AppKit renders blank / crash-guard only).
- **Data:** ArtifactCore + ArtifactStorage (SwiftData, versioning/export); PlaybookCore; PerformanceCore;
  SchedulingCore.
- **App integration:** `RuntimeKit` host (singletons, kill switch, scheduling engine, operator executor);
  Mission Control **tab** with all 14 sections: Home / Timeline / Activity / Sessions / Context /
  Approvals / Powers / Receipts / Operators / Artifacts / Playbooks / Routines / Performance / Mode.
- **Operators (P1-700):** Research Brief, active-identity Review, and read-only On-Chain Watch execute
  and produce artifacts. A separate prepared wallet action is blocked in Observe and escalates to the
  Approval Inbox in Assist — the crypto boundary is demonstrated end-to-end.
- A11yIDs registered in `AuraUI.A11yID.MissionControl`. ADR-008 (boundaries) + ADR-010 (crypto scope).

## Code follow-ups — DONE (post-M8 batch; app builds green)
- [x] #1 `ActionProposal.parameters` + concrete checks (address/ENS/chain-scope/freshness) registered;
      On-Chain Watch requires `chain.inScope`.
- [x] #2 Receipt signing wired into the chain (`signature`/`signerPublicKey`; signed on append; verified;
      exported). ReceiptStorage signing test passes.
- [x] #3 Unified governed path: `PipelineBackedPolicyGate` backs the app policy gate.
- [x] #4 Shared `RuntimeHost` via `RuntimeAssembly` (one host per container).
- [x] #5 `AppMode` → `CryptoMode` rename; alias deleted.
- [x] #6 SwiftData persistence for playbooks/performance/executions (`OperatorRuntimeStorage`, own
      on-disk container) via `RuntimeHost.persistent(...)`.
- [x] #7 BGTask handler + `.backgroundTask` scene wiring + Info.plist identifier.
- [x] #8 String Catalog pipeline (`defaultLocalization: en` + auto-populated `Localizable.xcstrings`).

## Remaining — code (small)
- [ ] Localization adoption (`bundle: .module` + translations) — **deferred by decision** to one future
      WWDC on-device/AI-translation pass across all packages. English ships today.
- [ ] **Post-completion follow-on — does not reopen the completed ownership and sovereignty restructuring:** populate
      the integrity-bound receipt contribution-provenance fields from production writers and define an explicit
      `ActorRef` to `PrincipalID` bridge where stable identity actually exists. The vocabulary is present but currently
      unused in live receipts.
- [x] ~~Two `ReceiptStorage` `reset*` tests fail in the bare sandbox~~ — **resolved/stale**: tests inject
      `InMemoryReceiptIntegrityHeadStore`; no test touches the Keychain head store. 7/7 pass.

## Remaining — device / review / design (cannot be closed by compiling)
- [ ] **BGTaskScheduler background firing on device** — code + Info.plist done; verify on hardware.
- [ ] **Secure-Enclave hardware path** — `SecureEnclaveReceiptSigner` fully implemented + wired via
      `ReceiptSignerFactory` with a persistent software fallback; verify Enclave signing/verify on a device
      (`SecureEnclave.isAvailable == false` on the simulator).
- [x] ~~Accessibility audit~~ — done in code (2026-08-13); on-device VoiceOver/Dynamic-Type sweep remains.
- [x] ~~Snapshot baselines~~ — empty (12) + populated (5) baselines recorded; iOS-simulator pixel-parity
      re-record optional if device rendering must match exactly.
- [ ] **Physical-device QA**: kill switch halts routines; approve/reject/defer; artifact export; receipt
      verify/export; privacy reset with the new stores. Suite: `Phase-1-Physical-Device-QA-Suite.md`.
- [ ] **App Review checklist** — work `Phase-1-App-Review-Checklist.md`; close open items in
      `Phase-1-Known-Limitations.md` before submission.

## Device verification steps (hardware only)

**BGTask background firing**
1. Run the app on a physical device (Debug build) so `RuntimeBackgroundScheduler.scheduleNextRefresh()`
   submits a `BGAppRefreshTaskRequest` for `com.auralis.runtime.refresh` at launch.
2. Pause the debugger and simulate a launch:
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.auralis.runtime.refresh"]`
3. Confirm `RuntimeBackgroundScheduler.runInBackground()` runs due routines (an `ExecutionRecord` appears
   in Mission Control → Performance) and that a fresh refresh is rescheduled.
4. Confirm the global kill switch (Home → "Pause all operator activity") short-circuits scheduled runs
   to no-ops.

**Secure-Enclave signing**
1. On a physical device, `SecureEnclave.isAvailable` is `true`, so `ReceiptSignerFactory.deviceSigner()`
   returns a `SecureEnclaveReceiptSigner` and persists the Enclave blob in the Keychain.
2. Append a receipt (run any operator) and open Mission Control → Receipts → detail → Integrity; confirm
   the chain verifies and `exportAll()` includes `signature` + `signerPublicKey`.
3. Relaunch and confirm the signing identity is stable (the persisted Enclave key is reused, not re-keyed).
