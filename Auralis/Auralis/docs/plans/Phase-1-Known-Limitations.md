# Phase 1 — Known Limitations (Mission Control / Operator Console)

Honest, tracked list of what is intentionally limited, deferred, or unverified in the Phase 1 operator
console as of **2026-10-22**. This is the doc the Physical-Device QA suite
(`Phase-1-Physical-Device-QA-Suite.md` → Exit Rule) and `OperatorConsole-Ship-Readiness.md` require
authored before an App Review submission. Deferred/major QA findings should be mirrored back into this
doc under **Open findings**.

Legend: **Deferred** = decided out of Phase 1 on purpose · **Unverified** = code complete, needs a
device/review to confirm · **Accepted** = a real limitation we ship with and disclose.

---

## L-01 — Localization: English-only (Accepted / Deferred)

The app is English-only. Package string-catalog wiring (`bundle: .module`) and translations are
deferred by decision (2026-08-13) to a single future WWDC on-device/AI-translation pass across **all**
packages, so no package is half-localized. English ships fine today. The accepted product stance
remains recorded by the memory note "localization-deferred-to-wwdc-pass".

## L-02 — BGTaskScheduler background firing: Unverified on device

Code + `Info.plist` `BGTaskSchedulerPermittedIdentifiers` (`com.auralis.runtime.refresh`) are complete
and re-verified; launch-time reschedule + handler → `runDueRoutines` is wired. Background *firing* has
never been confirmed on physical hardware (simulator/package tests cannot prove it). Closed only by
**MC-Device-010**.

## L-03 — Secure Enclave receipt signing: Unverified on device

`SecureEnclaveReceiptSigner` (CryptoKit SE P-256) is implemented and wired via `ReceiptSignerFactory`,
which persists the signing key in the Keychain (Enclave blob when available, else a stable software
P-256 key). On the simulator `SecureEnclave.isAvailable == false`, so the software fallback is what runs
in CI. The hardware Enclave path — SE signing, stable identity across launches, `exportAll()` carrying
`signature` + `signerPublicKey` — is confirmed only by **MC-Device-011**.

## L-04 — On-device accessibility sweep: Unverified

Accessibility was audited and fixed **in code** across all 14 Mission Control sections (2026-08-13):
VoiceOver selection state, combined non-interactive rows, Dynamic Type via text styles, semantic-color
contrast that is never the sole status carrier. The on-device VoiceOver / Dynamic-Type sweep on real
hardware is the residual and is not yet signed off.

## L-05 — Snapshot baselines are host-recorded, not device-parity: Accepted

17 image snapshots (12 empty-state + 5 populated) + logic tests are green on host via a cross-platform
`HostingController` + `.image` strategy. These guard structure/regressions, **not** pixel-parity with
device rendering. iOS-simulator/device pixel-parity baselines are an optional follow-up if exact device
rendering must be locked.

## L-06 — Seeded/sample operator data in the console: Resolved

Production no longer supplies a sample watch account. On-Chain Watch fails closed until the active
identity saves or enters an explicit chain-qualified target, then merges local receipt history with a
bounded read-only native-balance snapshot from the configured provider. UI fixtures remain test-only.
The distinct prepared-action path still proves Observe denial and Assist approval escalation without
granting signing or broadcast authority.

## L-07 — Production Phase 2 capabilities deferred (by design)

Phase 1 now includes bounded foundations rather than an empty Phase 2 surface. The advisory EvalCore
recommendation lifecycle cannot change playbooks, policy, capabilities, or authority. The integrated
`PlannerCore` / `AutopilotCore` POC is reachable through explicit user-triggered goal surfaces and routes
cleared steps through the governed runtime, but it is not unattended production autonomy and still needs
the documented physical-device verification. Basic scheduling exists; advanced triggers, windows,
dependency-aware execution, and production background behavior remain deferred.

Full outcome evaluation, production unattended autopilot, third-party operator packs, advanced scheduling,
autonomous multi-agent orchestration, stablecoin budgets/x402, agent mandates, self-improvement loops, and
advanced memory graphs are **not** Phase 1 shipping claims. P1-SOCIAL-101/102 is the bounded exception:
shared sessions, shared context, collaborative approval voting, and ritual execution are code-wired in
Mission Control, persisted locally,
and cleared by privacy reset. The Social relay path is now enabled in Debug and Release, but
production-public collaboration remains outside the Phase 1 shipping claim. Relay evidence and two-device QA remain
open, and wallet verification is still local to the joining installation: peers cannot independently verify a portable
signature, so remote binding actions fail closed. The production gate is defined by
`Social-v1-Abuse-and-Reliability.md`, `Social-v1-Relay-Readiness.md`, and
`Social-v1-Physical-Device-QA-Suite.md`.

## L-08 — Persistence retention policy: Accepted

Playbook / performance / execution stores are backed by SwiftData (`OperatorRuntimeStorage`, own on-disk
container) and survive relaunch. Social coordination now has bounded retention: complete terminal-session
graphs age out only when they have no pending outbound events, stale invites/cursors are removed with them,
and completed ritual-occurrence claims retain a bounded newest window. Active social histories are never
prefix-truncated because that would corrupt deterministic replay.

Two gaps here are now closed. **Worklog retention** is implemented in `SwiftDataWorklogStore`
(`maximumStoredSteps = 10_000`, matching the event-history cap): above the cap, whole *completed* workflows
are dropped oldest-first — by correlation group, never by row, since pruning rows would decapitate a trace
and make `steps(forCorrelationID:)` read as though the workflow began midway. Blocked, failed, escalated,
and still-running traces are never dropped, which makes the cap deliberately soft: a device carrying more
than the cap in unfinished work stays above it rather than deleting the evidence of why work stalled.

Because that soft cap makes "over the cap with nothing droppable" a steady state rather than an anomaly,
the sweep is not run on every write. It is O(rows) — a full table fetch plus a decode of each candidate
group — so re-running it per write would have made every worklog write O(rows) for exactly as long as the
table was largest. `SwiftDataWorklogStore` now records the size an unproductive sweep gave up at
(`unprunableFloor`) and waits for `pruneRetryGrowth = 256` new entries before retrying, bounding the
amortized cost to O(rows / 256) per write; recording a step that *completes* a workflow clears the backoff
at once, since that is precisely what makes a group droppable. The under-cap path stays a single
`fetchCount` aggregate that never materializes a row.

**Privacy reset now actually reaches these stores.** It previously did not: `resetTransactionalPrivacyData`
operates on the app's main model container, so the entire `OperatorRuntimeStorage` container survived
"delete all local data" — worklog traces (including proposal parameters, planner rationales, and
actor/authority attribution), agent sessions, execution records, performance events, event history, and
artifacts. `RuntimeHost.resetAllHistory()` clears all of them and is wired as the
`operatorRuntimeHistory` phase of `PrivacyResetService` (**MC-Device-012**), resolved through
`RuntimeAssembly.sharedHost` so rows from earlier launches are reached even when Mission Control was never
opened this session. Installed playbooks are deliberately left alone: the catalog is configuration, not a
record of activity. Retention for playbook/performance/execution history remains a Phase 2 decision.

## L-09 — Worklog unknown-case tolerance: Closed

Actor attribution and the worklog are code complete and CI-covered (`RuntimeCore`, `SchedulingCore`,
`RuntimeKit`, `OperatorsFeature`, `OperatorRuntimeStorage`, `ReceiptsCore`, `ReceiptStorage`,
`MissionControlFeature`); their contracts are documented in `../reference/Runtime-Kernel.md`
§Actor Attribution and §Worklogs. Two earlier gaps here were closed first: `OperatorsFeature`'s test target compiles
and is wired into CI (its four governed end-to-end tests had never executed), and an unreadable
`AuthorityRef` now degrades to "not recorded" via `AuthorityRef.decodedIfPresent(from:forKey:)` instead of
dropping the enclosing worklog entry, session, or execution record.

The last gap — `WorkflowWorklogEvent` and `RoutinePhase` throwing on a case this build does not recognize,
which the stores' `try?`/`compactMap` turned into silent deletion of the *whole entry* — is now closed by
`WorkflowWorklogEvent.unknown(caseName:payload:)`. Three properties make it a real fix rather than a
decoder tweak:

- **The entry survives.** Its actor, authority, correlationID, toolID, and timestamp are what make the
  surrounding trace legible; previously they were discarded along with the event, so a workflow read as
  though it had skipped a step rather than as though one step was unreadable.
- **The payload survives.** `WorklogRawJSON` carries the original JSON verbatim and re-encodes it under its
  original case name, so `.unknown` is a *rendering* degradation, not data loss: exports stay faithful,
  `WorklogExport`'s byte-stability contract still holds, and a build that understands the event reads the
  real thing back out of the export.
- **Nothing is deleted on the strength of it.** `SwiftDataWorklogStore.completesWorkflow(_:)` never counts
  `.unknown` as a completion, so retention cannot drop a trace this build failed to interpret.

`RoutinePhase` deliberately gained no `unrecognized` case, which would have forfeited the exhaustive-switch
guarantee every derivation depends on in order to serve one decoding path. A newer phase is handled a level
up instead: the `routinePhase` decode fails, the entry becomes `.unknown("routinePhase", …)`, and the raw
phase name is preserved inside the payload. Tolerance is triggered by *any* decode failure, not by an
allowlist of known case names, because an allowlist is a second place to update — one a future author could
forget, silently degrading a brand-new event on the very build that writes it. The cost is that genuine
corruption is no longer distinguishable from a downgrade at the type level; keeping the bytes is the better
trade either way. Covered by `WorklogUnknownEventToleranceTests` (RuntimeCore), whose round-trip case
guards against the `KnownWorklogEvent` mirror drifting out of sync.

---

## L-10 — Receipts written before Round 13 recorded placeholders instead of identifiers: Accepted (unrecoverable)

`DefaultReceiptPayloadSanitizer.resolvedValueKind(for:stringValue:)` tested its opaque-token
heuristic — `value.count >= 24 && ^[A-Za-z0-9_\-]{24,}$` — *before* honouring the kind the writer
declared. A 42-character `0x…` Ethereum address and a 36-character UUID string both match that
pattern, so an explicitly declared `.walletAddress`, `.hashed(kind: .walletAddress)`, or `.label`
was reclassified `.opaqueToken`, which `resolvedSensitivity` maps to `.redact`. The persisted value
became the constant string `<redacted-opaque-token>`, and the `looksLikeWalletAddress` branch below
it was unreachable for any real address.

**Fixed forward** in Round 13: the structured, fixed-length forms are now tested first
(`looksLikeWalletAddress`, plus a `UUID(uuidString:)` exemption), on the argument that neither shape
can launder a secret, while the heuristic still applies to genuinely unstructured `.unknownString`
values. Three test suites had pinned the broken output as correct and were corrected in the same
pass (`AuralisTests/ReceiptEventLoggerTests`, `ContextSnapshotTests`,
`AccountReceiptRecorderTests`, `MusicFeature`'s `MusicReceiptEventLoggerTests`).

**What cannot be recovered, and why it is disclosed rather than migrated.** For receipts already on
disk the identifier was never written — the placeholder replaced it before persistence, so there is
no encoded form to re-derive it from. Concretely, for pre-fix receipts:

- A playlist receipt cannot say *which* playlist it describes, so the `delete_playlist` rollback it
  advertises cannot be targeted, and two different playlists are byte-identical in their identity
  fields.
- `accountAddress` is a single constant rather than a per-account `sha256:` digest, so in-payload
  per-account correlation is impossible for those rows.
- Artifact-provenance links are absent: `ReceiptContentPresenter.artifactIDs(in:)` parses UUIDs, and
  it finds none.

The receipt **chain** is unaffected — integrity, sequence, and attribution columns never went
through the payload sanitizer, so no pre-fix receipt is unverifiable, merely less informative. A
backfill is not possible and a reset would destroy the history this contract exists to preserve.

**Residual: closed in the same round.** The first fix covered only fields carrying a *declared*
kind, which left every key nested inside an `.object` payload value still redacting — they have no
declared kind and are classified by `inferredValueKind(forKey:value:)` from the key alone. That was
live for `MusicReceiptStateSummary.playlist(…)`, which nests `playlistID` inside its
`beforeSummary`/`afterSummary` objects, so one receipt contradicted itself: the top-level field
named the playlist and both summaries said `<redacted-opaque-token>`.

`inferredValueKind` now applies the same UUID exemption, classifying a UUID as `.label`. Widening
the *kind* cannot widen the *sensitivity*, which is what makes this safe to apply to undeclared
keys across every package: `resolvedSensitivity(for:kind:stringValue:)` tests
`keyLooksSensitive(field.key)` before it looks at the kind, so a UUID-shaped credential under a key
naming a token, secret, or API key is still redacted on the strength of its key. The opaque-token
heuristic is untouched for everything that is not UUID-shaped. Pinned by
`nestedUUIDSurvivesSanitization`, `nestedUUIDUnderASensitiveKeyStillRedacts`, and
`nestedArbitraryTokenStillRedacts` (ReceiptsCore), plus
`playlistModificationSummariesNameThePlaylist` (MusicFeature), which asserts the top-level field and
both summaries agree.

The unrecoverable pre-fix window described above is unaffected by this second fix and remains the
accepted limitation this entry exists to disclose.

---

## L-11 — Post-completion ownership provenance adoption: Deferred

`PrincipalID`, `OwnershipDescriptor`, and the receipt contribution-provenance fields are defined, persisted,
integrity-bound, exported, decoded backward-compatibly, and covered by golden-vector and tamper tests. Production
receipt writers do not yet populate `principal`, `affectedResource`, `producedResult`, or `parentReceiptIDs`, and no
explicit `RuntimeCore.ActorRef` to `PrincipalID` bridge exists. The vocabulary is therefore structurally available but
does not yet answer those questions for live receipts. This is tracked in `P0-Future-Work.md` and the Phase 1 authority
audit; ownership metadata still grants no authority. This is optional production adoption after the completed
ownership and sovereignty restructuring, not an incomplete restructuring requirement or a Phase 1 release blocker.

## L-12 — Social relay is enabled before its production-readiness gates are closed: Unverified / release-blocking

`AURALIS_SOCIAL_RELAY_ENABLED` is `YES` in both Debug and Release. AES-GCM envelopes, missed-message recovery, local
controls, and fail-closed projection are implemented, but relay terms, quotas, retention, SLA, scaling evidence, and
the two-device suite remain open. In addition, the wallet connector currently returns a local Boolean ownership result
and discards the signature, so another installation cannot independently verify that participant and correctly keeps
them `.pending`. Public Social claims remain blocked despite the enabled configuration.

---

## Open findings (populated from QA)

Mirror `Blocker` / `Major` / deferred `Minor` findings from
`Phase-1-Physical-Device-QA-Suite.md` here, with severity, repro, owner, and status.

| ID | Severity | Summary | Repro / QA test | Owner | Status |
|---|---|---|---|---|---|
| _(none yet — device QA not run)_ | | | | | |
