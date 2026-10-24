# Phase 1 Physical Device QA Suite (Mission Control / Operator Console)

This is the real-device QA suite for the Phase 1 Mission Control operator console. The simulator is
useful for speed. It is **not** where BGTask background firing, Secure Enclave signing, app lifecycle
timing, and "does this governance actually hold in the hand?" issues tell the truth.

Automated UI/accessibility coverage is tracked separately in `P0-UI-Test-QA-Suite.md`. Passing
simulator UI tests does not replace this physical-device gate. Residual ship blockers this suite exists
to close are enumerated in `OperatorConsole-Ship-Readiness.md` → "Ship blockers."

The shipping scope for this suite is the assembled Phase 1 release path: the Mission Control tab
(`AppTab.missionControl`, labeled "Ops") over the shared `RuntimeHost` from `RuntimeAssembly.sharedHost`,
its 14 sections (Home / Timeline / Activity / Sessions / Context / Approvals / Powers / Receipts /
Operators / Artifacts / Playbooks / Routines / Performance / Mode), the durable receipt chain
(`ReceiptStores.live` + `ReceiptSignerFactory`), the persistent operator stores
(`OperatorRuntimeStorage`), and background scheduling (`RuntimeBackgroundScheduler` +
`SchedulingEngine`). The crypto boundary (`DomainJudge`, ADR-010) is in scope; wallet-provider
connection routes remain covered by `AuraPlay-Physical-Device-QA-Suite.md`.

## Test Environment Template

Record this before starting:

- device model
- iOS version
- app build/version
- build configuration (Debug vs Release — note that `AppTabBarVisibility.live` is `.all` in DEBUG and
  `.release` in Release; Mission Control ships in both)
- network condition: normal Wi-Fi, weak Wi-Fi, cellular, offline
- account used for testing and chain scope(s)
- crypto mode under test: Observe / Assist / Operate
- whether this is a clean install, upgrade install, or relaunch pass
- whether `SecureEnclave.isAvailable` is `true` on the test device (expected `true` on A-series/M-series
  hardware, `false` on the simulator)
- whether the operator stores are running through the persistent `OperatorRuntimeStorage` container or
  an in-memory fallback

## Exit Rule

Phase 1 real-device QA passes only when:

- all blocking tests below pass
- no crash, persistent loading wedge, or unrecoverable navigation state remains
- the global kill switch demonstrably halts new governed work and scheduled runs
- no receipt fails integrity verification, and no exported receipt/artifact is missing its signature or
  provenance
- the crypto Observe boundary blocks wallet-affecting steps with a denial receipt
- any known issues are documented with severity, repro steps, and owner, and mirrored into the Phase 1
  Known-Limitations doc

## MC-Device-001: Cold launch into Mission Control

Goal:

- verify the operator console is the default surface and launches cleanly over the shared host

Steps:

1. Install or launch a fresh build.
2. Enter a valid account.
3. Confirm the app opens on the "Ops" tab (default `selectedTab == .missionControl`).
4. Terminate and relaunch.
5. Confirm the Home console repopulates counts, live activity, and recent receipts.

Pass criteria:

- no blank root, crash, or frozen launch path
- Home shows Mode, Console status counts, Freshness & context, Controls, and Recent receipts on first
  and second launch
- the shared host is reused (pause state and history survive a tab switch away and back)

## MC-Device-002: Kill switch halts new and scheduled work (P1-204)

Goal:

- prove the global pause is a real governance control, not a label

Steps:

1. On Home, enable "Pause all operator activity" (`missionControl.pauseToggle`).
2. Confirm the paused banner (`missionControl.pausedBanner`) appears above every section with a reason
   and a Resume path.
3. Go to Routines and attempt "Run now" on an installed routine.
4. Go to Operators and attempt to run an operator.
5. Trigger a scheduled/background run (see MC-Device-010) while paused.
6. Resume via the banner (`missionControl.resumeButton`) and retry.

Pass criteria:

- "Run now" is disabled while paused; no new workflow starts
- a scheduled run that fires while paused short-circuits to a recorded no-op `ExecutionRecord`
- the paused banner is visible on all sections and its reason text is plain-language
- resuming re-enables governed work

## MC-Device-003: Approval inbox — approve / reject / defer (P1-201)

Goal:

- verify the approval decision loop writes durable, correct receipts and updates the inbox honestly

Steps:

1. Produce a pending approval (run an operator/playbook whose impact escalates, or launch with
   `-ui-testing-mission-control-fixtures` for a seeded approval).
2. Open Approvals (`missionControl.approvals`); confirm the risk chip, plain-language reason, and any
   linked plan/receipt/artifact.
3. Approve one item, reject another, defer a third.
4. Relaunch the app.

Pass criteria:

- approve and reject remove the item; defer leaves it pending
- after relaunch, approved/rejected items stay resolved (append-only receipts), deferred stays pending
- each decision writes an `approval.<decision>` receipt with capability, intent, reason, and risk
- approved receipt `isSuccess == true`, rejected `isSuccess == false`

## MC-Device-004: Capability inspector and revoke (P1-202)

Goal:

- verify lease inspection and revocation behave on device

Steps:

1. Open Powers (`missionControl.capabilities`).
2. Confirm active leases are grouped by scope (account / data / execution / artifact) with grant reason
   and duration text.
3. Revoke a lease from Powers, and separately from the Home "Revoke capabilities" section
   (`missionControl.home.revoke`).
4. Attempt work that depended on the revoked lease.

Pass criteria:

- revoked leases disappear from both surfaces
- subsequent governed work re-requests authority or is blocked rather than silently proceeding

## MC-Device-005: Receipt browser — verify and export (P1-301/302/303)

Goal:

- verify the durable receipt chain reads, verifies, and exports correctly on device

Steps:

1. Open Receipts (`missionControl.receipts.browser`).
2. Apply scope and outcome filters and a search query.
3. Open a receipt detail (`missionControl.receipt.detail`); confirm categorized sections and the
   correlated event timeline.
4. Verify chain integrity for the receipt.
5. Export all receipts and inspect the export payload.
6. Before opening that payload, capture the device fingerprint from the independently presented receipt provenance trust anchor.
7. Verify the export against that pre-pinned fingerprint; do not copy the fingerprint from the export being verified.

Pass criteria:

- chain verification passes for the full history
- `exportAll()` output includes `signature` + `signerPublicKey` for signed receipts
- filters and search return coherent results
- receipt → artifact links resolve to the correct artifact

## MC-Device-006: Artifact browsing, lifecycle, and export (P1-40x)

Goal:

- verify artifacts are first-class and their lifecycle controls work on device

Steps:

1. Produce an artifact by running an operator or an installed read/prepare playbook.
2. Open Artifacts (`missionControl.artifacts`); apply type/recency/workflow/account filters and toggle
   the history scope (`missionControl.artifacts.historyScope`).
3. Open an artifact detail (`missionControl.artifact.detail`).
4. Approve (`missionControl.artifact.approve`), export (`missionControl.artifact.export`), and supersede
   (`missionControl.artifact.supersede`) it; confirm version history.
5. Open the artifact via a deep link / routed artifact ID (relaunch into it if the route is exercised).

Pass criteria:

- exported artifact file contains the expected content and provenance
- supersede creates a new version and the version history reads correctly
- the routed-artifact path lands on the correct artifact detail (or a clear "not found" state)

## MC-Device-007: Playbook library — enable / pause / resume / edit (P1-502/504)

Goal:

- verify reusable playbooks (not one-shot) install and govern correctly on device

Steps:

1. Open Playbooks (`missionControl.playbooks`).
2. Create a new user playbook (`missionControl.playbooks.create`); set trigger, v0 flows
   (read/prepare only), capabilities, outputs, approvals.
3. Review & Enable via the authority-envelope review sheet.
4. Pause, then resume the installed playbook.
5. Attempt to enable a playbook whose flows fall outside the v0 read/prepare boundary.

Pass criteria:

- the authority envelope (capabilities, outputs, approval threshold, crypto-touch warning) is shown
  before enabling
- a playbook with execute-only flows cannot be enabled in v0 (Enable disabled)
- pause/resume moves the playbook between Installed and Paused states and persists across relaunch

Automated regression coverage:

- `MissionControlTests.playbookInstallRejectsExecuteFlowsAtModelBoundary`
- `MissionControlTests.playbookResumeRejectsPausedExecuteFlowsAtModelBoundary`
- `OperatorRuntimeStorageTests.playbookStoreSeedsUpsertsAndFilters`

## MC-Device-008: Routine manager and run-now (P1-503/601)

Goal:

- verify installed routines run, record, and respect governance on device

Steps:

1. Install a scheduled/event/maintenance playbook so it appears under Routines
   (`missionControl.routines`).
2. Confirm classification, last-run, and next-run text.
3. Use "Run now"; confirm an `ExecutionRecord` and a receipt appear.
4. Pause the routine and confirm "Run now" is disabled.
5. Confirm a no-op run still records an execution record.

Pass criteria:

- run-now produces a durable execution record + receipt and (if the operator emits one) an artifact
- paused routines cannot be run
- execution records are stored even for no-ops

Automated regression coverage:

- `MissionControlTests.routineManagerListsAutomaticRoutinesAndRunNowRecordsReceipts`
- `MissionControlTests.pausedRoutineRunNowRecordsNoOpWithoutProducingReceiptSuccess`
- `MissionControlTests.playbookStateAndExecutionHistorySurviveModelRecreationWithSharedStores`
- `SchedulingEngineTests.executionRecordsAccumulate`

## MC-Device-009: Crypto Observe boundary (ADR-010, P1-104/700)

Goal:

- prove the crypto-scoped Observe boundary holds on device end-to-end

Steps:

1. Set crypto mode to Observe (Mode section, `missionControl.mode`).
2. Run the On-Chain Watch operator (seeded account `vitalik.eth`) and confirm its read-only report is produced.
3. Select “Escalate prepared action” and confirm that separate wallet-affecting step is blocked with a denial receipt.
4. Switch to Assist/Operate and confirm the mode surfaces update their allowed-actions copy.

Pass criteria:

- in Observe, the watch report succeeds; the separate crypto preparation step is blocked and a denial receipt is written
- non-crypto operators (Research Brief, Identity Review) still run and produce artifacts in Observe
- the Mode section shows Observe/Assist/Operate as distinct surfaces with correct status

## MC-Device-010: BGTaskScheduler background firing (SHIP BLOCKER)

Goal:

- sign off the background scheduling path that cannot be proven by simulator or package tests

Steps:

1. Run the app on a physical device (Debug build) so `RuntimeBackgroundScheduler.scheduleNextRefresh()`
   submits a `BGAppRefreshTaskRequest` for `com.auralis.runtime.refresh` at launch.
2. Pause the debugger and simulate a launch:
   `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.auralis.runtime.refresh"]`
3. Confirm `RuntimeBackgroundScheduler.runInBackground()` runs due routines — an `ExecutionRecord`
   appears in Mission Control → Performance — and that a fresh refresh is rescheduled.
4. Engage the kill switch (Home → "Pause all operator activity") and repeat step 2.

Pass criteria:

- background firing runs due routines and reschedules the next refresh
- the background scheduler builds the host with the persisted crypto mode (not a forced Observe default)
- the kill switch short-circuits scheduled runs to recorded no-ops

Sign-off:

- Owner:
- Date:
- Device / iOS:
- Build:
- Result: Not Run

## MC-Device-011: Secure Enclave receipt signing (SHIP BLOCKER)

Goal:

- verify the hardware SE signing identity and its integration into the receipt chain

Steps:

1. On a physical device, confirm `SecureEnclave.isAvailable == true` so
   `ReceiptSignerFactory.deviceSigner()` returns a `SecureEnclaveReceiptSigner` and persists the Enclave
   blob in the Keychain.
2. Append a receipt (run any operator) and open Mission Control → Receipts → detail → Integrity; confirm
   the chain verifies and `exportAll()` includes `signature` + `signerPublicKey`.
3. Relaunch and append another receipt; confirm the signing identity is stable (the persisted Enclave
   key is reused, not re-keyed).
4. Perform a privacy reset (MC-Device-012) and confirm signing recovers cleanly afterward.

Pass criteria:

- SE-backed signatures verify on device
- the signing identity is stable across launches
- exported receipts carry signature + public key

Sign-off:

- Owner:
- Date:
- Device / iOS:
- Build:
- Result: Not Run

## MC-Device-012: Privacy reset with the operator stores

Goal:

- verify privacy reset clears operator/runtime state without corrupting the app

Steps:

1. Build up state: receipts, artifacts, installed playbooks, execution records, active leases.
2. Settings → Clear Local Privacy Data; confirm and complete the reset.
3. Relaunch and open Mission Control.

Pass criteria:

- receipts, artifacts, execution records, and leases are cleared from the operator stores
- Mission Control returns to a clean empty state (empty-state identifiers present) without crash
- receipt signing re-initializes and new receipts verify

## MC-Device-013: Lifecycle, scope changes, and offline turbulence

Goal:

- catch device-only lifecycle and scope-poisoning bugs in the console

Steps:

1. Switch accounts and chains while Mission Control is visited; return.
2. Background and foreground the app repeatedly with a workflow in flight.
3. Disable the network during a workflow and restore it.
4. Rapidly switch between sections while live events stream.

Pass criteria:

- live activity and counts stay coherent across backgrounding and scope changes
- no stale scope leaks into timeline/artifact/account filters
- offline turbulence degrades honestly rather than wedging a section

## Severity Rubric

- `Blocker`: crash, kill switch that fails to halt work, receipt integrity failure, missing signature on
  export, crypto boundary bypass in Observe, privacy-reset failure, unrecoverable navigation wedge
- `Major`: wrong approval resolution persisted, revoked lease still usable, routine runs while paused,
  artifact export missing content/provenance, background run not recorded
- `Minor`: polish issue, awkward animation, small visual defect, intermittent stale label without data
  corruption

## Final Test Report Template

- build tested:
- devices tested (and `SecureEnclave.isAvailable` per device):
- accounts/chains/modes tested:
- BGTask background firing result (MC-Device-010):
- Secure Enclave signing result (MC-Device-011):
- kill switch / approvals / capabilities / receipts / artifacts / playbooks / routines results:
- privacy reset result:
- blocker bugs:
- major bugs:
- minor bugs:
- deferred issues (mirror into Phase 1 Known-Limitations):
- go / no-go:
