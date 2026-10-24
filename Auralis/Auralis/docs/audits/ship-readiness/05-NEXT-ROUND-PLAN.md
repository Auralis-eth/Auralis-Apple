# Ship Readiness — Next Round Plan

> **Part of the `phased-build-out` ship-readiness audit, split across files in this directory.**
> Index and reading order: [README.md](README.md) ·
> [Status](01-STATUS.md) · [Findings](02-FINDINGS.md) · [Validation](03-VALIDATION.md) ·
> [Next Round Plan](05-NEXT-ROUND-PLAN.md) ·
> [Ship Gate](06-SHIP-GATE.md) · [Protocol](PROTOCOL.md)

---

**The continuation point. Superseded plans are kept below the current one, labelled.**

⚠️ **The plan is a hypothesis about where to look, not a scope definition.** Derive scope from git —
and note that *which* git command is correct has inverted twice on this branch: with the tree
committed, `git diff HEAD` is empty and reads as "nothing to audit". Use `git status --porcelain`
**and** `git log <last audited commit>..HEAD --stat`.

---

## Next Round Plan

### Round 23 — the accessibility product half, which is now the only open code work

⚠️ **This plan supersedes the Round 22 plan, reproduced below. Read the Round 22 entry in the Iterative Audit Log
first.** Round 22 completed that plan's item 0a — the unreviewed fix delta is read, its two defects are
fixed (F-114, F-115), and the whole tree is committed — so **the branch carries no unreviewed code for
the first time in this audit's history, and the Minor column is empty for the first time since Round
10.** What is left is not a reading problem.

**0. Scope derivation is still two commands, and this is the round most likely to get it wrong.**
`git status --porcelain` **and** `git log 22e6c80..HEAD --stat`. The tree was committed at Round 22
close, so `git diff HEAD` will be empty and will read as "nothing to audit" — the exact inversion that
made the Round 21 plan carry a warning about it. Being committed is not the same as being unchanged:
check for commits since, and remember this branch has already been committed-then-reopened once.

**1. The accessibility product half of F-105 — the round's substance, and the first round to attempt
it.** Five failures across seven tests, in three classes, measured twice with identical counts
(Round 19 and Round 21: 22 executed / 2 skipped / 8 failed) and untouched by any round so far:

- **Empty-frame `StaticText`** — `testHomeAccessibilityAudit`, `testReceiptsAccessibilityAudit`.
- **Text clipped** — `testNewsFeedAccessibilityAudit`, `testReceiptDetailAccessibilityAudit`, and now
  `testNFTAccessibilityAudit`, which Round 21 moved out of the harness class and into this one.
- **Dynamic Type partially unsupported** — `testSearchAccessibilityAudit`,
  `testMusicAccessibilityAudit`.

Three standing cautions, each already paid for: **do not pin element names** — they move between runs
(F-106), and a finding keyed to one is unreliable; **dump the hierarchy at the failure** rather than
reasoning about it, which is how both F-57 and the F-105 harness cause were actually found (F-104);
and **re-run anything you quote**, because these counts are the most-requoted numbers in the document.
`selectTab` now prints the tab bar on failure, so a harness regression is self-diagnosing.
The `xcode-integration:accessibility-dynamic-type-specialist` and
`accessibility-voiceover-specialist` skills exist for exactly the two largest classes here.

**2. Re-audit Round 22's own fixes — the standing item, and it has never once been wasted.** **Five
consecutive rounds have found a real defect in the previous round's fixes** (18, 19, 20, 21, 22), and
Round 22's own two findings were both in Round 21's fix rather than in the older code around it. The
delta to read is `22e6c80` and `5fcf709`. Specific questions: does `PrivacyResetPhase.receiptHistory`
leave any *other* caller or copy path assuming receipts are cleared by `.transactionalStore`
(`LocalDataStoragePolicy` was updated, but check Settings copy and any disclosure doc); and does the
split `catch` in `resetLocalPrivacyData` still append `completedPhases` in an order every later phase
reports correctly — Round 22 updated four existing assertions for the new phase, which is exactly the
kind of edit that can be made to pass rather than made right.

**3. Two shapes worth a dedicated sweep, because each has now been confirmed repeatedly.**

- **"A live path with no test", four confirmed hits (F-92, F-99, F-108, F-114).** F-114's instance was
  the sharpest yet: the test double *had* a `failure` property and no case ever set it, so the
  coverage looked present. Sweep for recording doubles with unexercised failure injection, and for
  guards whose deletion leaves the suite green.
- **"A correct mechanism with a false report", twice now (F-100, F-114).** The code does the right
  thing and the sentence beside it — comment, error copy, or receipt summary — describes something
  else. F-47 and F-49 were the same family. This is cheap to sweep for in user-facing copy: read every
  `errorDescription` and every `userMessage` against the branch that produces it.

**4. Owner actions, unchanged and still the gate.** F-53 (developer-account login, Push capability),
F-54 (CloudKit container plus the smoke test on hardware), the physical-device FoundationModels pass,
and hardware verification of F-101's keystore re-wrap. None are code and none can be done from this
repo; they are what "not ready to ship" currently means.

**Not in scope, by decision:** F-77 and F-78 (Phase 2), localization (deferred to the WWDC pass by
design — do not piecemeal-localize), and any Social external gate.

---

### Superseded plan for Round 22 — the unreviewed fix delta first, then the accessibility product work

✅ **Ran 2026-10-21 and completed its headline item.** Item 0a (the unreviewed fix delta) is done and
closed; the accessibility product work it named second was not attempted and carries forward as Round
23's item 1. Kept for the record of what the round was asked to do.

⚠️ **This plan supersedes the Round 21 plan, which ran on 2026-10-21. Items 0b and 1's harness half are
done; item 1's product half and item 2 are not. Read the Round 21 entry in the Iterative Audit Log before using
anything below.**

**0. Scope is `git status --porcelain` *and* `git log 82cb510..HEAD --stat` — both, because the branch
is in both states at once.** Round 21 opened with the tree clean and `82cb510` as HEAD; it ends with
**an uncommitted working tree again**, carrying two agents' work: Round 21's own fixes
(`StoredReceipt.swift`, `OperatorArtifactComposer*`, `AccountsFeature/**`, `PrivacyResetService.swift`,
`MainTabView.swift`, `AuralisApp.swift`, `AccessibilityAuditUITests.swift`, two new test files) **and a
concurrent agent's F-47/F-48/F-49/F-113 fixes** (`ActionPolicyGate.swift`, `StandingToolPolicy.swift`,
`PolicyCoreTests.swift`, `SwiftDataReceiptStore.swift`, `ReceiptLedgerReentrancyTests.swift`,
`MissionControlTests.swift`, `PolicyGateAndCollaboratorTests.swift`). Neither `git diff HEAD` alone nor
`git log` alone describes the branch. **And the owner action to commit the tree is back** — the Round 20
"tree is committed" state did not survive Round 21.

**0a. ⚠️ The highest-priority read is the fix delta nobody has reviewed — and this round it is two
distinct bodies of work, not one.**

- **F-47/F-48/F-49 + the F-113 liveness bracket (another agent's, ~290 insertions).** Round 21 did not
  read, run, or verify any of it and explicitly did not claim it; the rows say
  *"Fixed in the working tree, NOT audited"*. This is exactly the unreviewed-fix-delta position that
  produced a Blocker in **four consecutive rounds** (13, 14, 15, 16). Read it first. Specific questions:
  the `ActionPolicyGate` readiness-denial branch now writes a receipt where it previously returned bare
  — confirm that path cannot double-write with the Observe denial below it; `StandingToolPolicy`'s
  block reason changed from a schema identifier to user-facing copy, so check every test and UI surface
  that matched the old string; and the `liveLedgerAcquisitions` registration moved from
  `withLedgerLock` onto `runLedgerBody`, which is the F-113(b) question answered — verify the new
  bracketing claim ("no suspension point between the marker coming down and the remove") rather than
  inheriting it, since the previous version of that comment argued the opposite was harmless.
- **Round 21's own fixes.** F-107 changes a value that feeds the integrity chain; the argument that it
  is hash-neutral is written out in the register row and in `resolve`'s comment, and it should be
  re-derived independently rather than read. F-46's residual re-sequences a **destructive** user-facing
  path (privacy reset) — check the new phase ordering against `LocalDataResetError` reporting and
  confirm the real store, not a double, is wired in `PrivacyResetServices.live`. F-105's `MainTabView`
  change gates four previously-unconditional tabs; `.release` contains all five so production is
  unchanged, but **verify that claim against `AppTabBarVisibility.live` directly** rather than trusting
  this sentence.

**0b. ✅ Done in Round 21 — `Auralis-Full`'s accessibility class ran to completion** on iPhone 17 Pro Max
(26.5) with 32 GiB free: **22 executed, 2 skipped, 8 failed**, reproducing Round 19 and resolving the
three confounded Round 20 results. `testReceiptDetail` does **not** crash (it fails on *Text clipped*),
`testMusic` is **not** unreachable (it fails on *Dynamic Type*), and `testMissionControlArtifactBrowser`
passes. Those were disk-condition artefacts, correctly not filed. **Still check `df -h /` before any
full-plan run** — the cascade is real, it just did not bite this time.

**0b. Check `df -h /` before starting any full-plan run, and budget ~1 GB for the result bundle.** Round 20's
`Auralis-Full` run was killed at ~20 minutes with 2.1 GiB free and a 485 MB bundle still growing; memory's
`codesign-internal-error-means-disk-full` note makes disk exhaustion a known cascade source on this machine.
**Re-running `Auralis-Full` to completion is Round 21's first validation task**, because three failures from
Round 20's partial run — `testReceiptDetail` **crashed**, `testMissionControlArtifactBrowser` "application is not
running", and `testMusic` "tab is not reachable in this launch state" (where Round 19 saw Dynamic Type) — are
confounded by the disk condition and were deliberately **not** filed as findings. Decide them on clean evidence;
do not inherit them as either real or absent.

**1. F-105 — the product half, now the only open Important with code in it. ✅ The harness half is
closed; F-106 is closed.** Round 21 fixed the two "tab not reachable" failures by gating the four
previously-unconditional tabs on `showsInTabBar`, and `testSettingsResetConfirmation` now passes
outright. ⚠️ **But the product count did not move: five failures, now across seven tests**, because
`testNFT` stopped failing as a harness case and started failing as a product one. Current state,
measured twice:

| Class | Tests | Note |
| --- | --- | --- |
| Empty-frame `StaticText` | `testHome`, `testReceipts` | Names moved again in Round 21 — "1 scoped NFT" and "Library". **Do not key work to the name** (F-106). |
| Text clipped | `testNewsFeed`, `testReceiptDetail`, `testNFT` | `testNFT` is new to this class, not new as a failure. |
| Dynamic Type partially unsupported | `testSearch`, `testMusic` | Use `xcode-integration:accessibility-dynamic-type-specialist`; do not hand-audit fonts. |
| Skipped, unassessed | `testNowPlayingSheet`, `testNFTActionMenu` | Still skipped. The "0 skips" premise has been dead since Round 19. |

**Budget one full-class run (~10 min) per verification cycle** and expect several; that cost is what
stopped Round 21 taking the product half. The per-element detail in this row is evidence from one run,
never the thing a fix is keyed to.

⚠️ **And before diagnosing any of the three product classes: dump the hierarchy at the failure first.**
`selectTab`'s `XCTFail` now does this permanently. Round 21 tried a plausible fixture-only hypothesis
for the harness class, had it disproved by the app's own trace, and only found the real cause from a
dump — the third round to relearn F-104's lesson.

**2. The unread residual, now genuinely small.** After Round 20, and unchanged by Round 21 except where
noted: `SearchAssistantService` (960), `MainTabView`'s remaining ~1,190 lines, ~40 smaller app files,
the `MissionControlFeature` remainder (~880), `NFTLibraryFeature` (272), `ArtifactCore` (110), and
**~5,600 lines of tests**. Start with `SearchAssistantService` — it is the largest single unread file
left and it spans the CoreSpotlight/FoundationModels overlay seam, where memory records real API churn.
Then the tests, against the standing Loop 2 question: *does any test pin a defect as correct?*

⚠️ **Two entries on that list were modified in Round 21 while still unread at depth, which makes them
worse than unread, not better.** `MainTabView`'s tab-content builder was restructured (four tabs gated)
and `AccountsFeature` was split across two files — both by a round that was auditing the register, not
those files. Read them as changed-and-unaudited, not as residual.

**2b. F-113 — still the highest-value unread code on the branch, and now with a fix on top of it that
is also unread.** `82cb510` replaced the ledger lock's `assert(!LedgerLock.isHeld)` with a thrown
`ReceiptLedgerReentrancyError` and narrowed the condition to a per-store, per-acquisition liveness
check. **Read it before anything else in item 2:** it is the receipt spine, and it introduces a path on
which `append` can now *throw* where it previously trapped or hung — into best-effort recorders that
swallow the error.

⚠️ **Question (b) has been answered by a concurrent agent, in the working tree, and that answer is
itself unaudited** (see item 0a). The `defer` clearing `liveLedgerAcquisitions` **did** cover more than
the body, and registration has been moved onto a new `runLedgerBody(_:_:)` so it brackets the body
exactly, with a `liveLedgerAcquisitionsForTesting` seam and a `queuedCallerIsNotRegisteredAsLive` test.
So the comment that argued the wider window was harmless was wrong — which is the F-92/F-99/F-108 shape
landing again, exactly as this item predicted. **Verify the new bracketing claim rather than inheriting
it; the previous comment in that same position argued the opposite and was wrong.**

Questions **(a)**, **(c)** and **(d)** from F-113's Actionable fix column are **still open**: the new
silent-drop path into best-effort recorders, the still-unidentified escape route that produced the
original inherited marker (so the originating crash is not closed by any of this), and whether a
refused acquisition can leave a head row written without its receipt.

**3. Re-audit Round 20's own fixes before building on them.** ✅ *Correction: they are no longer
unstaged — `d903602` committed them, so read them via `git show d903602` rather than `git diff HEAD`,
which is now empty.* F-108's fix calls `restore()` on the
session-deleted path, which reconciles against `connector.sessions()`. **The question to ask: can the
connector still report a just-deleted session as live?** If the transport's session list lags the
delete event, `restore()` could re-hydrate a dead wallet. The fix follows the pattern
`accountsChanged` already established, and the IRN transport removes the session before yielding the
event, but this was reasoned about rather than tested against a lagging transport — a fake whose
`liveSessions` still contains the deleted topic is a ten-line test and the natural next adversarial case.

**4. Verify F-101 on hardware — still the highest-priority device-QA item.** The opportunistic
`.biometryCurrentSet` → `.biometryAny` re-wrap: that a `.biometryAny` key is actually minted, that a
re-wrapped seed opens under it, and that prompt behaviour is unchanged all need a signed build.
Round 20's F-110 fix means the advisory now appears correctly after a restore, so the device script
should include: reinstall → Restore Wallet Access → **confirm the advisory is visible immediately**
→ sign → confirm it clears and the address is unchanged. **F-53 gates this.**

**5. The owner actions, which remain the whole non-code critical path.** F-53 (no signed build can be
produced — still the single largest open item, and blocking item 4); the Release secrets; one
`xcodebuild archive` + export; the first green PR run; and `WalletConnectorDemo/` ship-or-delete.
✅ **"Commit the working tree" is done** — `d903602` landed all 308 entries, the tree is clean, and a
PR can now be raised. Plus the external Social gates,
live because the relay flag is `YES` and now *documented* as such in source (F-109): operator terms,
abuse reporting, and the physical-device Social QA route.

**5b. F-112 — decide `AccountsFeature`'s platform story (owner call, no shipping impact).** It claims
`.macOS("26.0")` while being iOS-only UIKit. Either drop the false claim from the manifest (one line;
note it does **not** make `swift build` pass, since SPM still builds for the host) or split the non-UI
value types out of the 1,572-line `AddressTextField.swift` and wrap the two view files in
`#if canImport(UIKit)`. Round 20 deliberately did neither. **Also add the 42-package `swift build`
host sweep to CI** — it is what found F-111, and nothing else in the pipeline builds these packages
for the host platform.

**6. Deferred by design.** **F-98** (`findingCount`, owner decision), **F-107** (F-100's write-side
half, behind a `#if DEBUG` assertion that does not exist in release), **F-78** and **F-77**
(documented Phase 2 dead ends), and the carried list from Round 17.

**7. The standing generalisations, one of them now three-for-three.** *A guard or path whose deletion
leaves the suite green is one that will eventually break silently* — **F-108 is its third confirmed
hit** (after F-92 and F-99), and the strongest yet, because the path had no test at all rather than a
weak one. *A comment asserting a change closes a hole is a claim to verify* — F-109 is its third hit
too (F-96, F-100). *A test that has never executed is not coverage, it is an assumption.* **Corollary,
now confirmed twice: any sweep, wait, or build reported clean needs a positive control.** Round 20's
`grep` returned "no matches found" on an unquoted glob, and two builds 0.03s apart were only trusted
after a deliberate type error proved the diagnostic path was live. **New this round: when a
pre-fix run disagrees with the mechanism you predicted, the run is right** — F-108's pre-fix failure
showed the *other* wallet's record surviving, which is what exposed the `load`/`delete` fallback
asymmetry as the true cause.

---

### Superseded plan for Round 19 (kept for the record)

### Round 19 — accessibility is the open item, and it is now measured

**0. Derive scope from `git diff HEAD --stat`, not from this plan.** Round 18 opened on the unstaged
delta because the Round 18 plan said so; the plan was stale and the owner corrected it mid-round,
which immediately found an Important (F-102). Re-measure first, every round.

**1. F-105 — five real accessibility findings, now with evidence.** Round 18 fixed the six launch-state
defects that were stopping these audits before they asserted anything, which is what produced the
findings. What remains is product work:

- `Home` — `"Preview"` `StaticText` has an **empty frame**. The string comes from
  `EnergyCardView.swift:42` via `AuraPill`, whose body applies `.accessibilityElement(children: .ignore)`
  plus `.accessibilityLabel(label ?? "")`. Start by confirming whether the reported element is the
  ignored child `Text` or the synthesized label, because the fix differs.
- `Receipts` — the same shape for `"Library"`.
- `NewsFeed` — **Text clipped**.
- `Search` and `Music` — **Dynamic Type font sizes are partially unsupported**. This is the Dynamic Type
  nutrition-label property and is design-touching; it was deliberately *not* attempted at the end of
  Round 18 rather than rushed. The repo has a skill for exactly this
  (`xcode-integration:accessibility-dynamic-type-specialist`) — use it rather than hand-auditing fonts.

**2. Two `selectTab` overflow gaps, and a warning about how to approach them.** `testNFTAccessibilityAudit`
and `testSettingsResetConfirmationAccessibilityAudit` fail with "not reachable from the tab bar or an
alternate app route". `tab.nftTokens` and `tab.profile` are both set correctly in `MainTabView`, so this
is `More`-overflow resolution, not a missing identifier. Note `openTabViaHomeLauncher` has **no `case
"Profile"`**, but adding one that repeats the four lookups `selectTab` already tried will not help —
those are the same four. **Get the hierarchy first.** Round 18 burned three run-cycles on F-57 guessing
before one diagnostic dump settled it in a single run; do not repeat that. Add a temporary dump, read
it, then fix.

**3. The unread residual, unchanged and still the largest review gap.** Not read line-by-line:
`AlchemyProposalSimulator` (299), `SearchAssistantService` (229), `SocialInviteExchangeView` (177) and
`Model` (147), `InAppWalletView` (174), `SettingsView` (159), `MainTabView` (137),
`AuralisWalletConnectionFeature` (124), `ContextService` (97), `AuralisApp` (93),
`RitualNotificationSettings` (83), `SocialInviteMint`/`Coding` (123), ~40 smaller app files, the
`MissionControlFeature` remainder (~880), `NFTLibraryFeature` (272), `ArtifactCore` (110), and **~5,600
lines of tests**. All covered only by the mechanical anti-pattern sweep. Start with
`AlchemyProposalSimulator` (the last pre-signing check a user sees) and the invite-exchange pair (the
live invite path, relay flag `YES`). Then the tests, against the standing Loop 2 question: *does any
test pin a defect as correct?*

**4. Verify F-101 on hardware — the highest-priority device-QA item, and it is new.** Round 18 added an
opportunistic re-wrap of legacy `.biometryCurrentSet` wallets inside `withSeed`. Its generation-slot
resolution is unit-tested, but **the Keychain I/O and the Enclave are not and cannot be here**: that a
`.biometryAny` key is actually minted, that a re-wrapped seed opens under it, and that prompt behaviour
is unchanged all need a signed build. This is custody code touching the only copy of a mnemonic-less
seed, so it must be exercised on a device before ship, including: fresh legacy wallet → sign → confirm
the advisory clears and the address is unchanged; and a forced failure mid-migration → confirm the old
generation still opens. **F-53 gates this.**

**5. The owner actions, which remain the whole non-code critical path.** F-53 (no signed build can be
produced — still the single largest open item, and now blocking item 4 as well); the Release secrets;
one `xcodebuild archive` + export; the first green PR run; `WalletConnectorDemo/` ship-or-delete; and
**committing the working tree** (308 files / 16,493 insertions) with an explicit pathspec. Plus the
external Social gates, live because the relay flag is `YES`: operator terms, abuse reporting, and the
physical-device Social QA route.

**6. Deferred by design.** **F-98** (`findingCount` counting monitoring gaps — owner decision, nothing
reads it), **F-100**'s write-side half (now guarded by a debug assertion; the stored-format change
touches a hashed column), **F-78** and **F-77** (documented Phase 2 dead ends), and the carried list
from Round 17.

**7. The standing generalisations.** Two have produced defects repeatedly, and Round 18 adds two more:
*a guard whose deletion leaves the suite green is a guard that will eventually be deleted* (F-99 was its
second confirmed hit); *a comment asserting a change closes a hole is a claim to verify, not a reason to
skip verifying* (F-100); and new this round — **a test that has never executed is not coverage, it is an
assumption**, which F-57 and F-105 proved twice in one round: six audits had been failing at launch for
their entire existence, and the one test that did run was asserting against a keyboard.
**Corollary, learned the hard way: any sweep or wait reported as clean needs a positive control.**
Round 18 produced two false greens — a zsh word-splitting bug that made a 178-file grep return nothing,
and an `xcodebuild` run from the wrong directory whose wait loop completed normally while the suite had
never started.

---

### Superseded mid-round plan for Round 19 (kept for the record)

### Round 19 — finish the unstaged app-target half, then settle F-57

**0. Derive scope from `git diff HEAD --stat`, not from this plan.** Round 18 opened on the unstaged
delta because the Round 18 plan said so, and the plan was stale — it predated the
`SocialCore`/`OperatorsFeature` commit and assumed the staged index was reviewed. The owner corrected
it mid-round and the correction found an Important (F-102). Re-measure first, every round.

**1. The honest gap Round 18 leaves, and it is the first item.** Round 18 read, at audit depth, the
whole package half and the whole app-target wallet-custody and Social-relay surface, plus
`RuntimeAssembly`, `RuntimeBackgroundScheduler`, `PersistedCryptoMode`, `LiveOnChainOperatorDataSource`,
`ModeState` and `PrivacyResetService`. It did **not** read, at audit depth: `AlchemyProposalSimulator`
(299), `SearchAssistantService` (229), `SocialInviteExchangeView` (177) and `Model` (147),
`InAppWalletView` (174), `SettingsView` (159), `MainTabView` (137), `AuralisWalletConnectionFeature`
(124), `ContextService` (97), `AuralisApp` (93), `RitualNotificationSettings` (83),
`SocialInviteMint`/`Coding` (123), ~40 smaller app files, the `MissionControlFeature` remainder (~880),
`NFTLibraryFeature` (272), `ArtifactCore` (110), and **~5,600 lines of tests**. All of it is covered by
the mechanical sweep and none of it line-by-line. Start with `AlchemyProposalSimulator` and
`SocialInviteExchangeModel`/`View`: the first is the last pre-signing check a user sees, the second is
the live invite path with the relay flag `YES`.

**1a. Then the tests.** 5,600 lines, never read this round, against the standing Loop 2 question:
*does any test pin a defect as correct?* That question has paid out repeatedly (F-61's six assertions,
F-66's three, the `SocialQueueApplier` fake). Round 18 spot-checked only the queue-applier fake.

**2. F-57, which is now actionable for the first time.** The symptom has moved to a **deterministic**
failure at `AccessibilityAuditUITests.swift:215` — `XCTAssertTrue(runButton.exists)` for
`missionControl.operators.run.operator.research.brief` — reproduced in isolation. The old
`pauseToggle` symptom passes, because the unstaged delta correctly replaced the opening
`waitForExistence` with `openMissionControlSection`, so **this assertion has very likely never
executed in this audit's history**. Discriminate the two candidates before fixing either: (a) a
reveal/scroll limit, since the "Inputs" section above the operator rows has grown substantially
(watch-network picker, watch address field, watchlist, identity row, disclosure caption), or (b) the
Research Brief operator genuinely not registered under `-ui-testing-mission-control-fixtures`, which
would implicate the new `LiveOnChainOperatorDataSource` wiring and would be a product defect rather
than a test one. Capture the element hierarchy at the failure; the plan log records only the queried
identifiers and does not discriminate.

**3. Apply the neuter-the-guard technique where Round 18 did not reach.** It paid out again in Round
18 (F-99) and the two packages the Round 18 plan originally named are still only partly swept:
`RuntimeKit` and `MissionControlFeature`. Round 18 swept `RuntimeCore` incidentally and found the one
hit there. The rule stands: *a guard whose deletion leaves the suite green is a guard that will
eventually be deleted.* Cheap, mechanical, and it has now produced five findings across two rounds.

**4. Close the two Round 18 items that are decisions, not defects.** **F-100** — correct the three
receipt-predicate comments regardless of whether the underlying write-side normalization is fixed,
because their current wording will stop a future round re-checking a hole that is still open.
**F-101** — decide whether to re-wrap pre-existing wallets off `.biometryCurrentSet` opportunistically
on a successful unseal, or to accept and disclose; and add an explicit *Accepted risks at ship* line
for the `.biometryAny` relaxation itself.

**5. The owner actions, unchanged and still the whole critical path.** None is something an audit can
do, and F-53 is still the single largest open item:

- **F-53 — the signing environment.** No signed build of this app can be produced, which transitively
  blocks the physical-device pass, QA sign-off, FoundationModels autopilot telemetry, and F-54's
  receipt-witness smoke test.
- The Release secrets (`AURALIS_HELIUS_API_KEY`, `AURALIS_WALLETCONNECT_PROJECT_ID`) into
  `Secrets.local.xcconfig`.
- One `xcodebuild archive` + export. `CODE_SIGN_IDENTITY` has only ever resolved to `Apple Development`.
- The first green PR run on a runner.
- `WalletConnectorDemo/` — ship, gitignore, or delete.
- **Stage and commit the working tree.** Round 18 is the third round to find that the unstaged
  portion is where the unreviewed code lives. Partial commits have now *helped* once — the
  `SocialCore`/`OperatorsFeature` commit retired a long-standing plan item — so continue, with an
  explicit pathspec (memory `phased-build-out-has-a-large-preexisting-index`).
- The **external** Social gates, now live obligations rather than future ones because the flag is
  `YES`: relay operator terms, abuse reporting, and the physical-device Social QA route.

**6. Deferred by design, catalogued not forgotten.** **F-98** (whether `findingCount` should count
monitoring gaps — owner decision; nothing in production reads it). The two documented Phase 2 dead
ends, so nobody re-derives them: **F-78** (an audio-server RPC timeout aborts the app during launch;
unfixable inside `AudioEngineController`) and **F-77** (peer-driven queue reconcile has never worked
in production). Plus the carried list: `SharedSession.vote` on an already-resolved approval;
`appendLocal`/`enqueueOutbound` not applying `clampedForStorage`; `RitualEngine.mostRecentOccurrence`
defaulting a weekly schedule's missing `weekday` to Monday; `SocialAssembly.participantID` falling
back to a bare UUID with no wallet connected; the `O(n)`-per-append session scan in `appendInbound`;
`MissionControlHomeModel.addOperatorWatchTarget`'s third chain normalization; and
`ReceiptBackedOperatorDataSource` filtering `identityID` with an untrimmed `lowercased()`.

**7. The generalisations, both still standing.** The original has produced seven defects and Round 18
found nothing new of its shape: *`.eventSpecific` events are policed by rules reading
`participants[…]`, and any such rule that treats "first write wins" as fact rather than a wire-ordered
race is the next defect.* The second is Round 17's and is now the higher-yield one, with F-99 as its
second confirmed hit. **Round 18 adds a third, from F-100:** *a comment asserting that a change closes
a hole is a claim to verify, not a reason to skip verifying — check the fix against the call site, not
against its own description.* F-96 was this inverted; F-100 is the dangerous direction, because a
comment claiming a hole is closed suppresses the next re-check.

---

### Superseded plan for Round 18 (kept for the record)

### Round 18 — the code is done; what is left is not code

**Round 17 closed the code item that eight rounds of this plan have led with.** Both named packages have
now been read **in full** — source *and* tests, 16,804 lines across two loops — and the round produced
**no Blocker and, for the first time, no defect of any grade inside the previous round's fix delta**. The
four-round streak (13→14, 14→15, 15→16, 16's own Loop 2) is broken. Round 17's own delta is **test-only
plus two source comments**: no production behaviour changed, the three neutered guards were restored
byte-exact (verified against the session-start diffstat), and every new assertion was observed failing
against the guard it pins. A Round 18 re-read of *that* delta is therefore cheap and low-yield — read it,
but do not make it the round.

**The one thing Round 17 changed about the risk picture, and it is not a defect.**
`AURALIS_SOCIAL_RELAY_ENABLED` is now **`YES`** in both xcconfigs, confirmed intentional. Fifteen rounds
of Social findings were graded on the standing assumption that the flag was `NO` and every relay path was
therefore a pre-flip gate. **That assumption is now false.** Nothing in `SocialCore` needs re-fixing —
Round 17 read it all and the authority model holds with the flag on — but the **external** gates the
Round 16 plan listed as the pre-flip conditions are now live obligations rather than future ones:

- Relay operator terms.
- Abuse reporting.
- The physical-device Social QA route.

These are owner items. No audit round can close them, and they are the only Social work left.

**1. The owner actions, which are now unambiguously the whole critical path.** Unchanged, and none is
something an audit can do:

- **F-53 — the signing environment.** No signed build of this app can be produced. This transitively
  blocks the physical-device pass, QA sign-off, FoundationModels autopilot telemetry (simulator inference
  fails by design) and F-54's receipt-witness smoke test. Still the single largest open item.
- The Release secrets (`AURALIS_HELIUS_API_KEY`, `AURALIS_WALLETCONNECT_PROJECT_ID`) into
  `Secrets.local.xcconfig`.
- One `xcodebuild archive` + export before anything relies on that path. `CODE_SIGN_IDENTITY` has only
  ever resolved to `Apple Development`.
- The first green PR run on a runner.
- `WalletConnectorDemo/` — ship, gitignore, or delete.
- **Committing the working tree**, with an explicit pathspec (memory
  `phased-build-out-has-a-large-preexisting-index`), and then a re-audit of the committed diff. Both named
  packages are still 100% uncommitted; `git log -- SocialCore OperatorsFeature` is empty.

**2. F-57 — accessibility, still unmeasured, and now measured as *definitely* unrun.** Round 17's app-plan
runs reported **18 not run**, every one an `AccessibilityAuditUITests` case, across two separate runs. So
B5–B9 cannot come off ⬜ on their existence. Note this also means `testMissionControlOperatorConsoleSmoke`
did not execute, so Round 15/16's record of it failing is neither confirmed nor contradicted — do not read
Round 17's "0 failed" as that failure having been fixed.

**3. The generalisation, now with a second form.** The original still stands and has produced seven
defects: *`.eventSpecific` events are policed by rules reading `participants[…]`, and any such rule that
treats "first write wins" as fact rather than a wire-ordered race is the next defect.* Round 17 found
nothing new of that shape, which is evidence the family is closed rather than proof. **The second form is
Round 17's own contribution, and it is the more useful one going forward:** *a guard whose deletion leaves
the suite green is a guard that will eventually be deleted.* Four of them were found in one round (F-92,
F-93, F-94, F-95), one of them protecting a live network-egress contract. The technique that found them is
cheap and should be standard: neuter the guard, run the suite, and if it stays green the guard has no test.
Apply it to `RuntimeKit` and `MissionControlFeature` next — they are the two packages with the most
behavioural guards that Round 17 did not touch.

**4. The two documented Phase 2 dead ends, so nobody re-derives them.** **F-78** (an audio-server RPC
timeout aborts the app during launch; cannot be fixed inside `AudioEngineController` — the output node and
the blocking RPC are inseparable there) and **F-77** (peer-driven queue reconcile has never worked in
production, because a peer's record is `.pending` on any device but its own).

**5. Deferred by design, catalogued not forgotten.** **F-98** is the one open finding Round 17 left: whether
`findingCount` should count monitoring gaps. It is an owner decision, not a defect — nothing in production
reads the field. Also carried forward from Round 17's deferred list: `SharedSession.vote` records a vote on
an already-resolved approval (local UI only); `appendLocal`/`enqueueOutbound` do not apply
`clampedForStorage`, so the clamp symmetry `SocialInvite` argues for is one-sided for locally-minted
envelopes (unreachable today — both local producers mint ids far under the 160 limit);
`RitualEngine.mostRecentOccurrence` defaults a weekly schedule's missing `weekday` to Monday rather than
refusing, which is the fabricated-scope pattern `OperatorCatalog.defaultParameters` and
`OperatorRequest.init(parameters:)` were each deliberately stripped of; and from earlier rounds,
`SocialAssembly.participantID` falling back to a bare UUID when no wallet is connected, the `O(n)`-per-append
session scan in `appendInbound`, `MissionControlHomeModel.addOperatorWatchTarget`'s third chain
normalization, and `ReceiptBackedOperatorDataSource` filtering `identityID` with an untrimmed `lowercased()`.

---

### Superseded plan for Round 17 (kept for the record)

**Read Round 16's delta first, then the freeze holds.** *Round 17 did this and found nothing in it — the
first round in four to come up clean on the previous round's fixes. Superseded by the Round 18 plan above.*

**The one code item, and it is the only one that has ever mattered.** Round 16's own fix delta —
~1,770 insertions across `SocialCore`, `OperatorsFeature` and `RuntimeKit` — has been reviewed only by
the pass that wrote it. **Four consecutive rounds have found a Blocker-grade defect in exactly that
position** (13→14, 14→15, 15→16, and Round 16's manual Loop 2 inside its own Loop 1). Round 15
declared the freeze while leaving its delta unread and three Blockers were sitting in it, two of them
regressions its own fixes introduced. Do not repeat that. Scope for Round 17 Loop 1 is the Round 16
delta, nothing else:

- `SocialEventLogSnapshot.inboundSequenceByEventID` — a **new persisted field**. Legacy payloads decode
  `?? [:]` and sort as 0. Check the sweep in `normalized()`, the clear-on-evict, and whether
  `(values.max() ?? 0) + 1` can ever be non-monotonic (analysis says no: assigned numbers are globally
  distinct, so pruning cannot create a collision — verify that).
- `relayMayOverwriteHeldRecord`'s two-disjunct rule, which is the subtlest thing in the round. The
  second disjunct is load-bearing for idempotence against an *already-reduced* projection; the first
  closes the rename. Satisfy yourself that no third direction is open.
- `relayMayAssertAnchoredAccount` — author-side, role-blind by construction. Re-derive that bypassing
  `mismatchedAccount` confers nothing, because every `.bindingAuthor`/`.ownerAuthor` event still hits
  `guard isLocallyMinted`.
- The `appendInbound` rewrite: confirm there is now genuinely **no** path that silently drops an
  inbound envelope, and that the replay cursor still advances on every one.

**Then apply the generalisation, which has now predicted two more defects.** `.eventSpecific` events
are policed by rules reading `participants[…]`; any such rule treating "first write wins" as fact
rather than a wire-ordered race is the next one. Rounds 15 and 16 between them anchored four
(`unprovenVerifiedIdentity`, `foreignRecordUpdate`, `mismatchedAccount`, `rebindsAccount`). An eighth
would have to be a *new* rule of that shape — check before adding one.

**Round 15's remaining code item is closed, not deferred.** `SocialQueueApplier` reconcile is
unreachable from the relay (`queueSnapshotPublished` is `.bindingAuthor` → `isLocallyMinted`). Verified
Round 16.

**Everything below this line is unchanged from the Round 16 plan and is still not code.**

**Round 15 closed the code items on this list.** The two-loop pass over `OperatorsFeature` and
`SocialCore` is finished; the `rejectionReason` restructure is landed and has now been audited by a
reader who did not write it; and the three receipt-integrity seams are verified sound. **What remains is
almost entirely not code**, which is the condition the freeze was waiting for.

**Phase 1 is frozen.** Anything found from here triages into Phase 2 / backlog rather than reopening
Phase 1 — unless it is a Blocker, which reopens by definition.

**1. The owner actions, which are now the whole critical path.** Unchanged since Round 7 and unchanged by
this round, because none of them is something an audit can do:

- **F-53 — the signing environment.** No signed build of this app can be produced. This transitively
  blocks the physical-device pass, QA sign-off, FoundationModels autopilot telemetry (simulator inference
  fails by design) and F-54's receipt-witness smoke test. It is the single largest open item.
- The Release secrets (`AURALIS_HELIUS_API_KEY`, `AURALIS_WALLETCONNECT_PROJECT_ID`) into
  `Secrets.local.xcconfig`.
- One `xcodebuild archive` + export before anything relies on that path. `CODE_SIGN_IDENTITY` has only
  ever resolved to `Apple Development`.
- The first green PR run on a runner.
- `WalletConnectorDemo/` — ship, gitignore, or delete.
- **Committing the working tree**, with an explicit pathspec (memory
  `phased-build-out-has-a-large-preexisting-index`), and then a re-audit of the committed diff.

**2. F-57 — accessibility, still unmeasured.** `AuralisUITests` is not in `Auralis-Full` and its 18
accessibility tests have never executed, so B5–B9 cannot come off ⬜ on their existence. Round 14's one
datum stands: `testMissionControlOperatorConsoleSmoke` fails reproducibly at
`AccessibilityAuditUITests.swift:192` on a `missionControl.pauseToggle` double-tap whose second tap does
not register — pre-existing, before any operator code runs — and two sibling tests are flaky under load.
Round 15 did not get to this; the agent assigned to it hit the session limit.

**3. The two documented Phase 2 dead ends, so nobody re-derives them.** **F-78** (an audio-server RPC
timeout aborts the app during launch; cannot be fixed inside `AudioEngineController` — the output node
and the blocking RPC are inseparable there) and **F-77** (peer-driven queue reconcile has never worked in
production, because a peer's record is `.pending` on any device but its own).

**4. The sentence a Round 16 should start from, if it enters `SocialSync` at all.** Five defects in
`rejectionReason` have now come from one shape. The generalisation, which is narrower and more useful
than "add another guard": **`.eventSpecific` events are policed by rules that read `participants[…]`, and
any such rule that treats "first write wins" as a fact rather than a race is the next defect.** Round 15
closed the two that remained (`unprovenVerifiedIdentity`, `foreignRecordUpdate`). A sixth would have to
be a *new* rule of that shape — which is exactly what to check before adding one.

**5. Before `AURALIS_SOCIAL_RELAY_ENABLED` is ever flipped.** F-22 is resolved and the guard-chain
restructure the Round 15 plan treated as the remaining code gate is landed and audited. The gates that
remain are **external** — relay operator terms, abuse reporting, and the physical-device Social QA route —
plus a deliberate re-read of `SocialQueueApplier`'s reconcile semantics, which Round 15 could not reach
and which is the one path where a relay message reaches the user's real library. The flag is `NO` in both
xcconfigs today, verified this round.

**6. Deferred by design, catalogued not forgotten.** Both Loop 2 reports carry "Deferred / below bar"
lists that are worth reading before Phase 2 work in these areas — notably: `SocialAssembly.participantID`
falls back to a bare UUID when no wallet is connected, so an invite minted in that state can never anchor
an owner (latent, since no production path publishes an owner record over the relay today); the
`O(n)`-per-append session scan in `appendInbound`; `MissionControlHomeModel.addOperatorWatchTarget` using
a *third* chain normalization that disagrees with `WatchTarget.chainKey`; and
`ReceiptBackedOperatorDataSource` filtering `identityID` with an untrimmed `lowercased()` while the
request side trims.

---

### Superseded plan for Round 14 (kept for the record)

**Round 14 is the Loop 2 adversarial pass, and it is intended to be the last one before freeze.**

The owner's framing, which this plan follows: Phase 1 is roughly 75–90% through its polishing
period, and there is now a real risk of spending more on reducing already-small technical risk than
on advancing Auralis. Round 13 does not entirely support the optimistic half of that — it found
three Blockers in packages earlier rounds had read — but it does support the shape: every fix was
local, none required architectural rework, and the round ends with no deferred findings.

**The question for Round 14 is one question, asked across the whole Phase 0–1 surface: *what would
make us regret starting Phase 2?* Fix only those things. Then freeze.** Anything found after that
triages into Phase 2 / backlog rather than reopening Phase 1.

Where to point it, in order:

1. **The cross-cutting seams, not the packages.** Round 13 read eight packages in isolation by
   design, and the briefs sent every cross-package concern to a "Cross-cutting" list rather than
   making it a finding. That list is the highest-value unread surface in the repo. Three items on it
   already look load-bearing: `ReceiptIntegrity.chainHash` defaults `envelopeVersion` to `.current`,
   so one verification call site that forgets to pass the row's stored version silently rebuilds a
   v1 envelope and brands the whole ledger tampered — consider removing the default so the compiler
   enforces it; an unrecognized `integrityEnvelopeVersion > .current` must verify as **unattested**,
   not tampered, or a build downgrade reproduces the "reset is the only exit" failure
   `ReceiptIntegrity` argues against; and `ReceiptRecord.signature` is optional with a `nil` default
   while `chainHash` needs no secret, so a fabricated unsigned row is self-consistent and the
   mapping that must catch it lives entirely in `ReceiptStorage`.
2. **Know which gate covers what, because this round briefly got it wrong.** Seven broken call
   sites survived a green app run, and the first reading — that `MissionControlFeatureTests` is
   uncovered — was wrong: CI runs it, and every one of the 16 packages touched this round has a
   lane (verified at close-out). The real statement is narrower and still worth acting on: **a
   green local `Auralis-Fast` run is not evidence about package test targets**, because app test
   plans contain only `AuralisTests`/`AuralisUITests` by design. Anyone validating a cross-package
   change locally has to run the package suites too, or wait for CI. Worth a line in `AGENTS.md`
   next to the build instructions, since the mistake is cheap to repeat.
3. **The three still-unpinned behaviours Round 13 could not test.** `OperatorRuntimeStorage`'s two
   rollback guards (no injectable SwiftData save failure was found — three approaches are recorded
   in the test file so the next round does not re-derive them), and `LegacyArtifactMigration`'s
   `didFail` branch. Code-reviewed only.
4. **Close F-57 before claiming anything about accessibility.** Add `AuralisUITests` to
   `Auralis-Full`, clear the accessibility entries from its skip list, then *triage the results* —
   those 18 tests have never executed, so their pass rate is unknown. B5–B9 cannot come off ⬜ on
   their existence.
5. **Then the owner actions, which are the actual critical path** and have been since Round 7: the
   Release secrets (`AURALIS_HELIUS_API_KEY`, `AURALIS_WALLETCONNECT_PROJECT_ID`); F-53's signing
   environment, which transitively blocks the physical-device pass, QA sign-off, FoundationModels
   telemetry and F-54's receipt-witness smoke test; one `xcodebuild archive` + export before relying
   on that path; the first green PR run on a runner; `WalletConnectorDemo/` — ship, gitignore, or
   delete; and **committing the working tree** (439 entries), with an explicit pathspec.
6. **Before the relay flag is ever flipped:** resolve **F-22**.

---

### Superseded plan for Round 12 (kept for the record)

Recommended order for **Round 12**, continuing the owner-directed loop over the 21 named packages.
Round 11 closed items 1–4 of the Round 10 plan (F-44, `ReceiptsCore`, and — via F-56 — a great deal
more than was asked of it) and added one item that outranks most of what is left.

> **Ordering rule Round 11 established, worth keeping:** take packages by
> *unread-depth-at-current-size*, not by Review Ledger state. Several packages marked 🔬🧪 have
> roughly doubled since the round that read them (`PerformanceCore` 305 L → 1,025 insertions;
> `EvalCore` 804 L → 1,810; `OperatorRuntimeStorage` 1,310 L → 2,431), and `SchedulingCore`
> (2,035 insertions) has never been a Review Ledger area at all — it appears in this document only
> as a test count.

> **And run the app plan every round, even when every package suite is green.** F-56 was invisible
> to `swift test` by construction: the entitlement that caused it exists only in the app bundle.
> Eleven rounds of package-suite evidence could not have found it.

**Round 12 (planned):** `SocialCore` (4,239), `SchedulingCore` (2,035, never ledgered),
`OperatorRuntimeStorage` (2,431). Then Round 13: `EvalCore`, `PerformanceCore`, `PlaybookCore`,
`AutopilotCore`, `PlannerCore` — including the four new `AutopilotCore/Runtime/` files that put a
`JudgeDecision` in the step-authorization path, which should be read for fail-closed behaviour first.
Round 14: `OperatorCore`, `OperatorsFeature`, `ArtifactCore`, `ArtifactStorage`, `TrustedUIKit`.
Round 15: `AuraUI`, `ProviderKit`, `AuralisShellCore`, `MusicFeature`, `NFTKit`, then a combined
re-audit of the whole post-fix diff.

**0. Owner action, and it now gates the meaning of every green result: stage the two untracked
load-bearing receipt files.** `ReceiptsCore/Sources/ReceiptsCore/Models/ReceiptIntegrity.swift`
(defines `ReceiptIntegrity`, `ReceiptIntegrityEnvelope`, both column structs) and
`ReceiptStorage/Sources/ReceiptStorage/ReceiptPersistenceStore+Verification.swift` (999 lines, the
whole verify-and-export surface) are untracked. SPM compiles what is on disk, so everything passes
here and a fresh clone has no `ReceiptIntegrity` type — ReceiptsCore fails, then ReceiptStorage, then
the app. Explicit pathspec (memory `phased-build-out-has-a-large-preexisting-index`).

**0b. Close F-57 before claiming anything about accessibility.** Add `AuralisUITests` to
`Auralis-Full`, clear the accessibility entries from its skip list, then *triage the results* — those
18 tests have never executed, so their pass rate is unknown. B5–B9 cannot come off ⬜ on their
existence.

Carried forward from the Round 10/11 list, unchanged:

> Unlike Rounds 5–9, Round 10's plan was **extended rather than superseded** — items 1–5 below are
> new, and every item from the Round 10 plan is carried forward intact as items 6–15, since all of
> them remain open. There is therefore no "Superseded plan for Round 10" section.

1. **Close F-44 and the family it belongs to.** F-39, F-40, and F-44 are one shape — a single
   unreadable row condemning the whole ledger. Two are fixed; this is the third. Apply F-32's
   listing-vs-`get` rule, and add the F-42 residual test (an unrecognized `modeRawValue` re-hashes
   correctly) in the same pass. This is the only open FAIL.
2. **Audit `ReceiptsCore`.** It owns `ReceiptProvenanceExport`/`ReceiptProvenanceManifest`, and the
   single design compromise in Round 10's F-40 fix was keeping that wire format frozen because the
   package was out of scope — so the export contract is now load-bearing and unread. It is also where
   `ReceiptRecord.mode`/`.actor` decode as typed enums, the other half of F-42.
3. **F-47, then F-48/F-49 (PolicyCore).** F-47 is ~6 lines and guards a defect that has *already
   shipped once* (F-50). F-48's two branches went live the moment `ReceiptMode` gained cases.
4. **Then `ArtifactStorage` and `PlaybookCore`.** `ArtifactStorage` is the package whose
   `StoredArtifactForwardCompatibilityTests` / `ArtifactWriteRollbackTests` this audit keeps citing as
   the reference pattern — worth confirming the reference holds, because F-44 would make it three
   instances of one shape rather than a one-off. `PlaybookCore` is **entirely new** (416 insertions, no
   history) and its only external contact so far produced F-41.
6. **Owner action, still the critical path: supply the Release secrets.** `AURALIS_HELIUS_API_KEY`
   and `AURALIS_WALLETCONNECT_PROJECT_ID` into `Secrets.local.xcconfig`, then re-run Release with
   no overrides. Unchanged since Round 7.
7. **Owner action: commit the working tree** (~484 entries). Rounds 8 and 9 made this safe; Round 10
   committed one package out of it (`90628e5`, `AuralisPrimaryModels` only, explicit pathspec) and
   left everything else — including its own CapabilitiesCore/ReceiptStorage fixes — uncommitted.
   Use an explicit pathspec (memory `phased-build-out-has-a-large-preexisting-index`).
8. **Re-audit the whole post-fix diff once committed.** Blocked purely on item 7.
9. **Accessibility B5–B9 outside TrustedUIKit** — MissionControl, `InAppWalletView`,
   `SocialInviteExchangeView`. Still the **largest remaining checklist gap**.
10. **Archive and distribution signing.** `CODE_SIGN_IDENTITY` has only ever resolved to
    `Apple Development`. One `xcodebuild archive` + export before relying on the path.
11. **Confirm the first PR run is green.** Note Round 8 changed the lint lane (F-34: pinned 0.63.2,
    `--strict`); it has been verified locally at the pinned version but never on a runner.
12. **`WalletConnectorDemo/`** — ship, gitignore, or delete. Owner's call, the last untracked
    directory.
13. **Physical-device pass** — FoundationModels autopilot telemetry (simulator inference fails by
    design), plus Mission Control reachability on a compact iPhone.
14. **Optional:** the back half of `RuntimeHost` (~1,200 L of presentation/query plumbing) is the
    only partially-read file left. Round 6 covered its governance-critical surface.
15. **Before the relay flag is ever flipped:** resolve **F-22**.

### Starting a fresh session on this audit

Read **Metadata → Summary → Scope of Changes → Iterative Audit Log → the Round 10 entry in Audit
History → this plan**, in that order. Then, before reading any code:

- **Re-measure scope.** `git diff --name-only main | wc -l` and `git status --porcelain | wc -l`
  (Round 10: 624 / 484).
- **"All code has been read" is true by file, not by depth.** Round 9 closed on that basis and
  Round 10 then found two Blockers in already-"read" files, because no round had examined what
  `verifyIntegrity()` *does with* a signature. When a package's uncommitted diff is large (ReceiptStorage
  was ~700 lines in one file), treat it as unread regardless of ledger state.
- **Run the app test plan before believing a green package suite.** Round 10's packages were all green
  while an app-hosted assertion still failed. `-only-testing:AuralisTests/<Suite>` is ~2.5 min; the
  full plan is ~18 s of tests behind a ~2.5 min build.
- **Run *both* repo-state checks.** `grep -E '^[AMR]D'` must be empty (F-2) — **and** cross-check
  `grep '^D '` against `grep '^??'` for half-recorded renames, which the first check cannot see
  (F-38). Also check `git status --porcelain -- Auralis/AuralisTests | grep '^??'` is empty: five
  audit-authored tests, including F-18's entire fix, sat untracked for five rounds because
  synchronized folders run them from disk regardless.
- **Toolchain.** `export DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer`.
- **Lint with the *pinned* binary.** The `swiftlint` on `PATH` here is a stale **0.47.0** reporting
  34 serious violations on a tree the pinned **0.63.2** reports 0 on. Use the plugin binary under
  `DerivedData/Auralis-*/SourcePackages/artifacts/swiftlintplugins/…/macos/swiftlint`, run it
  **from `Auralis/`**, and check the count is 835.
- **A red app-plan run is not evidence until it survives `xcodebuild clean`.** Round 9 burned three
  full runs on a stale `Auralis.swiftmodule` that made the test bundle link a pre-fix implementation
  and report exactly the tests that fail pre-fix. If a failure set matches the known pre-fix set,
  suspect the build before the code.
- **App tests need an iOS 26+ simulator** (deployment target is iOS 26.0). iPhone 17 Pro on iOS 27
  runs all 590 with zero skips.
- **Do not re-audit anything marked 🔬🧪.** Nothing first-party is unread.
- **The seven open findings are all Observations** and deliberate. F-22 has a hard trigger (close it
  before the relay flag is ever `YES`); F-28 is a constraint on future work, not a defect.

---

### Superseded plan for Round 9 (kept for the record)

1. **Owner action, and still the critical path: supply the Release secrets.** `AURALIS_HELIUS_API_KEY`
   and `AURALIS_WALLETCONNECT_PROJECT_ID` into `Secrets.local.xcconfig`, then re-run Release with no
   overrides. Unchanged from Round 8; nothing an auditor does moves this.
2. **Owner action: commit the working tree.** ~494 entries. Round 8 staged the three new test files
   so nothing in the named packages is untracked, but the tree as a whole is still uncommitted, so
   the audited state is not the shippable state and no PR can be raised.
3. **`Aura/Receipts` (15) and `Assemblies` (9)** — now the only app-target code never audited, and
   carried since Round 3. F-31 came out of `Assemblies`. This is the largest remaining *review* gap
   on the branch and should go first among the engineering items.
4. **Finish RuntimeKit**: `RitualCoordinator` (652 L), `AutopilotStepExecutor` (646 L), and the back
   half of `RuntimeHost`, all read only around their session/dispatch seams. Sweep for A5.
5. **Archive and distribution signing.** `CODE_SIGN_IDENTITY` has only ever resolved to
   `Apple Development`. One `xcodebuild archive` + export before relying on the path.
6. **Confirm the first PR run is green** — and note the CI lint step changed in Round 8 (F-34:
   pinned 0.63.2, `--strict`). That lane has been verified locally at the pinned version but has
   never executed on a runner, so watch it specifically on the first run.
7. **Remaining Round 0 questions:** Q-3 (app-target membership for the remaining untracked app
   files), Q-6, Q-8, Q-9. **Q-7 is closed** — Round 8 settled it, and it was a non-issue.
8. **Accessibility beyond TrustedUIKit** — MissionControl, `InAppWalletView`,
   `SocialInviteExchangeView` are unassessed.
9. **Physical-device pass** — FoundationModels autopilot telemetry (simulator inference fails by
   design).
10. **Before the relay flag is ever flipped:** resolve **F-22**.

### Starting a fresh session on this audit

Read **Metadata → Summary → Scope of Changes → Iterative Audit Log → the Round 8 entry in Audit
History → this plan**, in that order. Then, before reading any code:

- **Re-measure scope.** `git diff --name-only main | wc -l` and `git status --porcelain | wc -l`
  (Round 8: 616 / 494). Re-run `git status --porcelain | grep -E '^[AMR]D'` — it must be empty, or
  F-2 is back.
- **Toolchain.** `export DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer`.
- **Lint with the *pinned* binary, not `swiftlint` on `PATH`.** This machine's Homebrew copy is
  **0.47.0** and reports 34 serious violations on a tree the pinned **0.63.2** reports 0 on. Use
  `…/DerivedData/Auralis-*/SourcePackages/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint`,
  run it **from `Auralis/`**, and check the file count is 833. Two different traps now sit on this
  one line (wrong directory → 11,594 files; wrong binary → a fabricated 34). The count is the
  checksum for the first, `--version` for the second.
- **App tests need an iOS 26+ simulator.** Deployment target is iOS 26.0; iOS 18.x devices are
  refused with a mismatch that reads like a toolchain crash. iPhone 17 Pro on iOS 27 runs all 580
  with zero skips.
- **Release needs the two missing secrets**, or `ValidateReleaseSecrets.sh` refuses it by design.
- **Do not re-audit anything marked 🔬🧪.** Every named package, both runtime packages, the artifact
  packages, and the app test plan are now covered. The value left is `Aura/Receipts`, `Assemblies`,
  and the back half of RuntimeKit.
- **The six open findings are all Observations** and deliberate. F-22 has a hard trigger (close it
  before the relay flag is ever `YES`); F-28 is a constraint on future work, not a defect.

---

### Superseded plan for Round 8 (kept for the record)

1. **Owner action, and now the critical path: supply the Release secrets.** Add
   `AURALIS_HELIUS_API_KEY` and `AURALIS_WALLETCONNECT_PROJECT_ID` to `Secrets.local.xcconfig`, then
   re-run the Release build with no overrides. Round 7 proved the compile is sound; this is the only
   thing between here and a genuine Release artifact. Nothing downstream — archive, TestFlight,
   device QA — can start without it.
2. **Owner action: commit the working tree.** ~493 entries. Until then the audited state is not the
   shippable state and no PR can be raised.
3. **Archive and distribution signing.** `CODE_SIGN_IDENTITY` resolves to `Apple Development` under
   automatic signing — fine for a local build, never exercised against a distribution profile. Do
   one `xcodebuild archive` + export to confirm the signing path before relying on it.
4. **`Aura/Receipts` (15) and `Assemblies` (9)** — the last app-target code never audited. Note
   F-31 was found in `Assemblies`, so this area has already produced one defect.
5. **Finish RuntimeKit**: `RitualCoordinator` (652 L), `AutopilotStepExecutor` (646 L), and the back
   half of `RuntimeHost` were read only around their session/dispatch seams. Sweep for A5.
6. **Confirm the first PR run is green.** The CI lanes have been verified individually but CI has
   never executed with them — and it has never run the app plan either, which now passes locally.
7. **Remaining Round 0 questions:** Q-3, Q-6, Q-7, Q-8, Q-9. Q-7 (`PrimaryStoreSchema` migration) is
   the last unexamined persistence risk.
8. **Accessibility beyond TrustedUIKit** — MissionControl, `InAppWalletView`,
   `SocialInviteExchangeView` are unassessed.
9. **Physical-device pass** — FoundationModels autopilot telemetry (simulator inference fails by
   design).
10. **Before the relay flag is ever flipped:** resolve **F-22**.

### Starting a fresh session on this audit

Read **Metadata → Summary → Scope of Changes → Iterative Audit Log → the Round 7 entry in Audit
History → this plan**, in that order. Then, before reading any code:

- **Re-measure scope.** `git diff --name-only main | wc -l` and `git status --porcelain | wc -l`.
  Re-run `git status --porcelain | grep -E '^[AMR]D'` — it must be empty, or F-2 is back.
- **Toolchain.** `export DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer`.
- **Lint from `Auralis/` and confirm the count is 831 files.** From the repo root SwiftLint finds no
  config and silently lints 11,594 files. The count is the checksum.
- **App tests need an iOS 26+ simulator.** Deployment target is iOS 26.0; every iOS 18.x device is
  refused with a mismatch that reads like a toolchain crash. Use iPhone 17 Pro on iOS 26.5 or 27.
  iOS 27 is the one that runs all 580 with zero skips.
- **Release needs the two missing secrets**, or it fails at `ValidateReleaseSecrets.sh` by design.
- **Do not re-audit anything marked 🔬🧪** in the Review Ledger unless a new finding implicates it.
  Every named package, both runtime packages, and now the app test plan are covered; the value left
  is in `Aura/Receipts`, `Assemblies`, and the rest of RuntimeKit.
- **The six open findings are all Observations** and deliberate. F-22 has a hard trigger (close it
  before the relay flag is ever `YES`); F-28 is a constraint on future work, not a defect.

---

### Superseded plan for Round 7 (kept for the record)

1. **Get one green app-target test run.** Now the single largest evidence gap: **0 of ~80 app test
   files have executed in any round**, including two this audit wrote (F-18's mirror test, Round 3's
   derivation tests). The app compiles clean in Debug, so the obstacle is the beta's app-hosted test
   crash (memory `xcode-beta-app-hosted-tests-crash`), not the code. If the beta still crashes, say
   so explicitly and record it as an accepted risk rather than leaving the line unchecked in silence.
2. **`Aura/Receipts` (15) and `Assemblies` (9).** Never audited, carried since Round 3. The
   assemblies are where store/host ownership and lifetime mistakes concentrate — F-23 came from
   exactly that seam, and F-27 shows the runtime is sensitive to *when* stores are first read.
3. **Finish RuntimeKit.** Round 6 covered the governed spine; `RitualCoordinator` (652 L) and
   `AutopilotStepExecutor` (646 L) were read only around their session and dispatch seams, and the
   back half of `RuntimeHost` (~1,200 L) is unread. Sweep those two for A5 specifically — the pattern
   has now hit four times.
4. **Release-configuration build + the line-by-line `Auralis-Release.xcconfig` review** the gate
   asks for. Only Debug has ever been built.
5. **Follow F-23 to its source.** `RuntimeBackgroundScheduler.runInBackground()` opening its own
   `ModelContainer` is what creates the second host; sharing the app's container (or memoizing on the
   store URL rather than the container object) removes the duplication rather than making each store
   tolerate it. F-28 is the reason this still matters.
6. **Confirm the first PR run is green.** The 13 CI lanes added in Round 4 were each verified
   individually but CI has never executed with them.
7. **Remaining Round 0 questions:** Q-3, Q-6, Q-7, Q-8, Q-9. Q-7 (`PrimaryStoreSchema` migration) is
   the one still carrying a Blocker hypothesis and the only unexamined persistence risk left.
8. **Accessibility beyond TrustedUIKit** — B5–B9 are PASS for that component only; MissionControl,
   `InAppWalletView`, and `SocialInviteExchangeView` are unassessed.
9. **Before the relay flag is ever flipped:** resolve **F-22**.
10. ~~**Optional cleanup:** F-8's snapshot budget from a measurement, and F-3, F-9, F-11.~~ **All four
    done in Round 6.** No Minor findings remain open; the six that are open are all Observations.

### Starting a fresh session on this audit

Read **Metadata → Summary → Scope of Changes → Iterative Audit Log → the Round 6 entry in Audit
History → this plan**, in that order. Then, before reading any code:

- **Re-measure scope.** `git diff --name-only main | wc -l` and `git status --porcelain | wc -l`
  (Round 6: 615 / ~493). Also re-run `git status --porcelain | grep -E '^[AMR]D'` — it must be empty,
  or F-2's index/worktree divergence is back and the audited state is not the shippable one.
- **Toolchain.** `export DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer`.
  Bare `swift test` crashes on the CLT toolchain.
- **Lint from `Auralis/` and check the file count is 831.** See the warning in Round 6's Validation.
- **Do not re-audit what is marked 🔬🧪 in the Review Ledger** unless a new finding implicates it.
  Every named package and both runtime packages are now line-read; the value left is in the app
  target and in *execution*, not re-reading.
- **Treat `Open (informational)` findings as context, not as a queue.** The six open Observations are
  deliberate; F-22 is the only one with a hard trigger (close it before the relay flag is ever set to
  `YES`), and F-28 is a constraint on future work rather than a defect.

---

### Superseded plan for Round 6 (kept for the record)

1. ~~**Audit RuntimeKit and RuntimeCore (T0, both still ⬜).**~~ **Done in Round 6 — it was a
   Blocker (F-27)**, the fourth A5 instance on the branch and the first to refuse *authority*. The
   prediction in this line held: the reentrancy question was open exactly where the concurrency
   lives. The governed spine is now line-read; `RitualCoordinator`, `AutopilotStepExecutor`, and the
   back half of `RuntimeHost` carry forward as Round 7's item 3.
2. **Get one green app-target test run** on a working toolchain. Still **0 of ~80 app test files
   executed in any round**, which now includes `TrustedUIA11yIDMirrorTests` (F-18) and
   `InAppWalletDerivationTests` (Round 3). Round 5's Debug `BuildProject` shows the app compiles, so
   the remaining obstacle is the beta's app-hosted test crash, not the code.
3. **`Aura/Receipts` (15) and `Assemblies` (9)**, never audited — carried over from Round 3 and
   Round 4. The assemblies are where store/host ownership mistakes concentrate, and F-23 came from
   exactly that seam.
4. **Release-configuration build**, plus the line-by-line `Auralis-Release.xcconfig` review the gate
   asks for. Only Debug has been built.
5. **Follow F-23 to its source.** `RuntimeBackgroundScheduler.runInBackground()` opening its own
   `ModelContainer` is what produces the second host; sharing the app's container (or memoizing on
   the store URL rather than the container object) removes the duplication instead of only making
   the stores tolerant of it.
6. **Confirm the first PR run is green.** The 13 CI lanes added in Round 4 have been verified
   individually in their CI form but CI itself has never executed with them.
7. **Remaining Round 0 questions:** Q-3, Q-6, Q-7, Q-8, Q-9. Q-7 (`PrimaryStoreSchema` migration) is
   the one still carrying a Blocker hypothesis.
8. **Accessibility beyond TrustedUIKit** — B5–B9 are PASS for that component only; MissionControl,
   `InAppWalletView`, and `SocialInviteExchangeView` are unassessed.
9. **Before the relay flag is ever flipped:** resolve **F-22** (`verificationState` is self-asserted
   and the wallet proof is not transported, so a receiver cannot verify it).
10. **Optional cleanup, if convenient:** F-8's snapshot budget from a measurement, and F-3, F-9, F-11.

---

### Superseded plan for Round 5 (kept for the record)

1. ~~Resolve Q-10 first.~~ **Done in Round 4 — it was a Blocker (F-23)** and is fixed. Related
   follow-up worth doing: `RuntimeBackgroundScheduler.runInBackground()` opening its own
   `ModelContainer` is what produces the second host in the first place. Sharing the app's container
   (or memoizing on the store URL rather than the container object) would remove the duplication at
   its source rather than only making the stores tolerant of it.
2. ~~Close F-16 and F-17.~~ **Done in Round 4.** Lint is 0/829 across 27 roots; 13 CI lanes added
   and each verified in its CI form. Confirm the first PR run is green, since CI itself has not yet
   executed with the new lanes.
3. **Audit RuntimeKit and RuntimeCore (T0, both still ⬜).** 120 Swift files of governance kernel,
   the largest unread surface on the branch. Given A5 has now failed in three separate files
   (F-1, F-14, F-20), sweep specifically for check-or-read → `await` → write-back before anything else.
   **Round 5 ran that sweep over the 23 named packages and found no fourth instance; RuntimeCore and
   RuntimeKit were deliberately not entered, so this carries forward as Round 6's item 1.**
4. **`Aura/Receipts` (15) and `Assemblies` (9)**, still never audited — carried over from Round 3's plan.
5. ~~**Deep-read the named packages still not line-read:** `OperatorRuntimeStorage`, `EvalCore`,
   `PlaybookCore`, `PerformanceCore`, `CapabilitiesCore`.~~ **Done in Round 5 — F-24 (Important),
   F-25, F-26.** All 23 named packages are now line-read. The warning held: F-24 sat behind a fully
   green suite too.
6. ~~Fix F-20.~~ **Done in Round 4.**
7. **Get one green app-target test run** on a working toolchain. Still 0 of ~80 app test files executed
   in any round, which now includes `TrustedUIA11yIDMirrorTests` (F-18) and Round 3's
   `InAppWalletDerivationTests`.
8. **Remaining Round 0 questions:** Q-3, Q-6, Q-7, Q-8, Q-9.
9. **Accessibility beyond TrustedUIKit** — B5–B9 are now PASS for that component only; MissionControl,
   `InAppWalletView`, and `SocialInviteExchangeView` are unassessed.
10. **Before the relay flag is ever flipped:** resolve **F-22** (`verificationState` is self-asserted and
    the wallet proof is not transported, so a receiver cannot verify it).

---

### Superseded plan for Round 3 (kept for the record)

1. **`InAppWalletSigner` (293 L) and `InAppWalletDerivation` (112 L).** The last two
   irreversible wallet-custody paths, both unread. Round 2 found a funds-loss Blocker in
   the first custody file it opened, so treat these as the highest-probability location
   for the next one. Check BIP-32/44 derivation against known test vectors, and check
   what the signer does with the seed's lifetime.
2. **Make `InAppWalletKeystore` testable and cover F-6.** Extract the Keychain behind a
   protocol the way `ReceiptSigningKeyStoring` does, then assert what
   `ReceiptSignerFactoryTests` already asserts for receipts: a write failure must not
   produce a usable-looking wallet. Without this, the Blocker fix is unguarded.
3. **`Aura/Receipts` (15) and `Assemblies` (9)** — never audited; the assemblies are
   where store/host ownership and lifetime mistakes concentrate.
4. **The remaining 25 wallet/Social files**, starting with `AlchemyProposalSimulator`
   (279 L) and `SocialRelayCoordinator` (247 L).
5. **Establish the missing validation baseline:** direct SwiftLint run, navigator
   sweep, and one `Auralis-Fast` run (budget ~12 min, run backgrounded).
6. **Remaining Round 0 questions:** Q-3, Q-6, Q-7, Q-8, Q-9.
7. **Accessibility pass** (B5–B9) on TrustedUIKit, `InAppWalletView`, and
   `SocialInviteExchangeView`.
8. **Set F-8's snapshot budget from a measurement**, and fold in F-3/F-9 if convenient.

Depth on the governed and security-critical spine remains worth more than a shallow
sweep of everything.

---
