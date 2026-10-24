# Ship Readiness — Ship Gate & Final Assessment

> **Part of the `phased-build-out` ship-readiness audit, split across files in this directory.**
> Index and reading order: [README.md](README.md) ·
> [Status](01-STATUS.md) · [Findings](02-FINDINGS.md) · [Validation](03-VALIDATION.md) ·
> [Next Round Plan](05-NEXT-ROUND-PLAN.md) ·
> [Ship Gate](06-SHIP-GATE.md) · [Protocol](PROTOCOL.md)

---

**The gate that must be fully checked before any ship claim, and the standing verdict.**

⚠️ **The verdict block's counts are reconciled *from*
[01-STATUS.md](01-STATUS.md)'s Metadata row, which is the one being maintained.** These two have
drifted apart after almost every round that closed findings; if they disagree now, Metadata is right
and this file is stale.

---

## Handoff & Verification Gate

Every line must be checked, with evidence recorded in **Validation**, before Current
Status may become 🟢 Ready to Ship.

### Pre-ship verification

- [x] **Builds** — `BuildProject` succeeds, 0 errors, Debug **and** Release. *(Round 7: Debug ✅
      0 errors; Release ✅ **0 errors, 0 warnings** — but only with stand-in values for the two
      secrets this machine lacks. A real Release build is blocked on the owner supplying
      `AURALIS_HELIUS_API_KEY` and `AURALIS_WALLETCONNECT_PROJECT_ID`; the gate refuses without
      them, by design.)*
- [x] **Unit tests pass** — package suites via `swift test` with Xcode-beta `DEVELOPER_DIR`;
      app suites via a test plan. *(Round 7: packages **1,281 passing**; app `Auralis-Full`
      **580/580 on iOS 27**, and 578 passed / 0 failed / 2 availability-skipped on iOS 26.5. First
      app-target execution in the audit's history — it caught F-31. Round 8 re-ran the app plan
      after its fixes: **`** TEST SUCCEEDED **`, 0 failures, 0 skips**, and the 23 named packages
      at **603 passing**, with every consumer of the changed artifact store re-run on top.)*
- [x] **UI / snapshot tests pass** — Library/Player and Mission Control baselines current.
      *(MusicFeature 118/118 and MissionControlFeature 115/115, Round 5, baselines unchanged.)*
- [x] **SwiftLint clean** — plugin binary run directly, not read from the navigator.
      *(Round 8: `--strict`, **0 violations / 0 serious in 833 files** at the pinned **0.63.2**.
      ⚠️ The binary matters as much as the directory: `swiftlint` on this machine's `PATH` is a
      stale 0.47.0 and reports **34 serious** on the same tree. That discrepancy is what produced
      **F-34** — CI was installing an unpinned SwiftLint and running it without `--strict`, so the
      lane enforced neither this rule set nor this severity. Both fixed.)*
- [x] **Compiler warnings triaged** — count recorded, each either fixed or accepted with a reason.
      *(Round 8: Debug `buildForTesting`, 14 log entries → **3 distinct warnings**. Two fixed —
      redundant `#require` in `SocialInviteExchangeTests`, dead `?? "nil"` in
      `TestStringConvertibleExtensions`. One **accepted**: `Evaluations.framework` built for 27.0
      linked against an iOS 26.0 deployment target, an Xcode-beta SDK artifact with no code-side
      remedy. Release was **0 warnings** in Round 7.)*
- [ ] **No open ❌ FAIL findings** — every Blocker resolved; every Important resolved or
      documented-and-accepted below. ⚠️ **Flipped back to unchecked on 2026-10-21: the Round 6
      parenthetical this line carried ("0 Blockers, 0 Importants, 0 Minors") has been false since
      Round 10 and was never updated.** Current open set, reconciled against the Findings Register
      at **Round 22** close: **1 Blocker — F-53** (code signing; release engineering, not a code
      defect). **3 Important — F-54** (CloudKit witness, owner action), **F-105** (accessibility;
      harness half closed in Round 21, **5 product failures across 7 tests remain**), **F-78**
      (AuraPlay launch robustness, deferred to Phase 2) — plus **F-51 accepted** below and **F-101
      fixed-in-code pending device verification**. **0 Minor** — F-47/F-48/F-49 and F-113 were read
      and closed in Round 22, and F-114/F-115 were opened and closed in it. Open Observations by
      choice: F-4, F-5, F-12, F-21, F-28, F-50, F-52, F-77. This line cannot be re-checked until
      F-53/F-54 clear and the accessibility product half lands.
- [ ] **Final diff re-audited after all fixes** — including changes made during the audit.
      *(Rounds 8 and 9 each re-audited their own changes and re-ran the full plan at round close.
      What is still owed is one pass over the **whole** post-fix diff once the tree is committed.
      ⚠️ **This briefly became reachable and then did not happen.** The tree was clean at `d903602`
      and `82cb510`; no round took the whole-diff pass in that window, and Round 21 reopened the
      tree, so the line is blocked on a commit again — now with 298 insertions of another agent's
      unreviewed fix delta inside it.)*
- [x] **Working tree committed** — the audited state equals the shipped state. ✅ **Re-closed at
      Round 22 close, after one reopen.** `d903602` landed all 308 entries on 2026-10-20 and three
      commits followed it; Round 21 then wrote **21 entries / 1,375 insertions** back into the tree,
      two agents' work in one undifferentiated delta; Round 22 read the unreviewed half of it and
      committed everything in **seven commits grouped by finding**. ⚠️ Checked, not retired — this
      item has now been closed twice and reopened once, so re-verify it rather than inheriting the
      tick. Mechanics unchanged: commit with an **explicit pathspec** (memory
      `phased-build-out-has-a-large-preexisting-index`), never `git stash push -- <path>` here.
- [ ] **Untracked files resolved** — added to the correct target, gitignored, or deleted.
      *(Round 8 closed this for the 23 named packages. Round 9 fixed **F-38**, three half-recorded
      `MusicApp` renames that would have deleted files on commit, and staged this round's two new
      app test files. What remains is the owner's call, not an auditor's: `WalletConnectorDemo/`
      needs a ship/gitignore/delete decision, and the rest of the untracked app files get resolved
      by the commit itself.)*
- [x] **Release config reviewed** — `Auralis-Release.xcconfig` line-by-line; Social relay
      flag state deliberate and recorded; no secrets; no debug-only flags enabled. *(Round 7. Found
      and fixed **F-30** and **F-29**. `Secrets.local.xcconfig` gitignored and untracked; no
      debug-only flag in Release; `-O` + whole-module confirmed from the build log.* ⚠️ **The relay
      flag state recorded here was `NO`; re-verified directly on 2026-10-21 it is
      `AURALIS_SOCIAL_RELAY_ENABLED = YES` in **both** `Auralis-Debug.xcconfig:3` and
      `Auralis-Release.xcconfig:3`.** The line stays checked because the state is deliberate and
      owner-confirmed (2026-10-12), not because it is unchanged — but it means **Social v1 ships
      live, not flag-gated**, so every Social finding is a live defect rather than a pre-flip gate,
      and the external gates (relay operator terms, abuse reporting, physical-device Social QA)
      are open owner items. The assignment still sits after `#include? "Secrets.local.xcconfig"`,
      so a developer cannot override it locally — which now means they cannot switch the relay
      **off** either. Read the xcconfig every round; this value has flipped three times.)*
- [ ] **Apple Developer account re-authenticated** (F-53) — automatic signing can currently update no
      profile at all. *(Found 2026-09-29 while validating the receipt-witness entitlement against a
      signed destination: `Unable to log in with account 'redrivercolony.eth@gmail.com'. The login
      details ... were rejected.` **Pre-existing and independent of the witness work** — it blocks
      every capability change, so it is the first domino for the two witness lines below and for the
      Push item after it. Simulator builds and both test plans are unaffected, which is why ten
      rounds of green builds did not surface it.)*
- [ ] **Push Notifications capability provisioned** (F-53) — `aps-environment` is in
      `Auralis.entitlements` but the profile does not carry the capability. *(Same signed-build
      attempt, same day: `Provisioning profile "iOS Team Provisioning Profile: ETH.Auralis.Auralis"
      doesn't include the Push Notifications capability`. **Pre-existing**, not introduced by the
      witness work. Recorded here because a signed device build cannot succeed until it is resolved,
      and no simulator run will ever reveal it.)*
- [ ] **CloudKit receipt-witness container provisioned** (F-54) — **owner action; cannot be done from the
      repo.** *(The external witness for the receipt ledger — see `ReceiptLedgerWitnessing` — needs
      the container `iCloud.ETH.Auralis.Auralis` created in the Apple Developer portal, associated
      with app identifier `ETH.Auralis.Auralis`, and picked up by the provisioning profile. The
      entitlement is already in `Auralis.entitlements`
      (`com.apple.developer.icloud-services`, `com.apple.developer.icloud-container-identifiers`),
      and a signed build fails until the portal side matches: `Provisioning profile ... doesn't
      support the iCloud.ETH.Auralis.Auralis iCloud Identifier`. **The entitlement identifier and
      `AURALIS_RECEIPT_WITNESS_CLOUDKIT_CONTAINER` must be byte-identical** — a mismatch silently
      addresses a different container rather than failing, so the ledger would read as witnessed
      while nothing publishes for it.)*
- [ ] **CloudKit receipt-witness enabled and smoke-tested on a signed physical device** (F-54) — **owner
      action; no device is attached to the audit machine.** *(Set
      `AURALIS_RECEIPT_WITNESS_CLOUDKIT_CONTAINER = iCloud.ETH.Auralis.Auralis` in **both**
      `Auralis-Debug.xcconfig` and `Auralis-Release.xcconfig` — it ships **empty**, which leaves the
      witness off and verification reporting every ledger as unwitnessed. Then, on hardware: fresh
      install → append receipts → confirm a `ReceiptLedgerCheckpoint` record appears in the private
      database's `AuralisReceiptLedgerWitness` zone; relaunch → `verifyIntegrity()` is `.verified`;
      append past the checkpoint → still `.verified`; airplane-mode append then reconnect → the
      "not been confirmed against the external witness" advisory clears. Until this runs, the three
      properties the witness exists for — suffix truncation, whole-account deletion and
      below-checkpoint rewrite becoming `.tampered` — are covered **only** by the in-memory double,
      never against real CloudKit.)*
- [ ] **Physical-device pass** — FoundationModels autopilot telemetry on hardware
      (simulator inference fails by design).
- [ ] **Mission Control reachable on compact iPhone.**
- [ ] **ADRs updated** where this branch changed an architectural boundary.
- [ ] **PR opened against `main`.** (Target release is ASAP-on-readiness; no date to assign.)
- [ ] **QA signed off** — physical-device QA suites executed and recorded by the human owner.

### Accepted risks at ship

List each Important finding being shipped unfixed, with the reason and who accepted it.
If there are none, state that explicitly.

| Finding ID | Severity | Reason for acceptance | Accepted by | Date |
| --- | --- | --- | --- | --- |
| F-51 | Important | **Accepted for Phase 1 — asynchronous witness publishing.** The receipt ledger publishes its witness checkpoint *after* the append commits, so receipts written since the last successful CloudKit write are outside anything the witness can vouch for, and an attacker who removes only those is not detected. Accepted because the alternative — awaiting a network round trip inside `append` — puts CloudKit in the critical path of every receipt, so an offline device could not record its own audit trail: that trades a narrow, bounded gap for an outright loss of history. Publishing on every append keeps the window one receipt wide whenever the network is healthy. The window is `nil`-safe in both directions: an unreachable witness degrades to an advisory and never accuses, and a witness that answers and *disagrees* is still hard `.tampered`. Documented at `ReceiptPersistenceStore.publishWitnessCheckpoint(...)` with the two follow-ups (durable publish-pending queue; witness outside the Apple account) recorded as non-blockers. | `pharms.eth` | 2026-09-29 |
| F-52 | Observation | **CloudKit private database is not a third-party witness**, and the ledger's guarantees should not be described as though it were. It raises the bar from "write one file on the device" to "write that file **and** compromise an iCloud account" — which is the whole gap six review rounds kept finding holes in — but Apple holds the store and the account owner can delete the zone. A ledger that must survive the account owner needs a transparency log or a public-chain commitment. Recorded rather than fixed because nothing in the product currently requires protection against the account owner; stated in `CloudKitReceiptLedgerWitness`'s own documentation so the limit travels with the code. | `pharms.eth` | 2026-09-29 |
| F-44 | Important | ✅ **No longer an accepted risk — resolved in Round 11, and this row was left stale for ten rounds.** It was entered here in Round 10 as "not accepted, open and unassigned" pending an owner decision; Round 11 fixed it instead, so no acceptance was ever needed. Kept as the historical record of the decision point, not as an open item. See the Findings Register row for what the fix does and why `exportAll()` still refuses on purpose. | *n/a — fixed* | 2026-09 (R11) |
| — | — | **Re-reconciled against the Findings Register on 2026-10-21 (Round 21 close).** Every **Blocker** raised across twenty-one rounds is resolved **except F-53**, which is release engineering rather than a code defect and is not eligible for acceptance — it blocks device QA outright. The only Important item still open is **F-54** (owner action: CloudKit witness provisioning); **F-105** and **F-78** are resolved in code as of 2026-10-21, and **F-101** is fixed in code and awaiting hardware verification. Three Minor — **F-47/F-48/F-49** — are fixed in the working tree but **unaudited**, and **F-113** is recorded ungraded, so neither group is eligible for acceptance until someone reads them. The **8** Observations open by choice: **F-28** is a constraint on future work rather than a reachable defect, **F-50** is un-migratable by nature, **F-77** is deferred to Phase 2, and **F-4/F-5/F-12/F-21/F-52** are informational. *(The earlier version of this row also listed **F-22** as "gated behind a flag that is `NO` in both Debug and Release" — stale twice over: F-22 was **resolved in Round 14**, and `AURALIS_SOCIAL_RELAY_ENABLED` has been **`YES`** in both xcconfigs since 2026-10-12, so no Social finding is flag-gated any more. Always read the xcconfig; memory `social-v1-shipped-public-with-accepted-risk`.)* ⚠️ Note for whoever next edits this table: the Round 10 F-44 row above sat here contradicting the register for ten rounds — reconcile this table at every round close, not when it looks wrong. | — | — |

### Sign-off

No signature may be entered while any verification line above is unchecked.

| Role | Name | Verdict | Date | Notes |
| --- | --- | --- | --- | --- |
| Auditor (LLM) | *model + tooling of the final round* | ⬜ | | Must be the round that re-audited the post-fix diff. |
| Author | `pharms.eth` | ⬜ | | |
| QA | `pharms.eth` | ⬜ | | Physical-device QA suites executed by the human owner. |
| Release owner | `pharms.eth` | ⬜ | | Final ship decision. |

---

---

## Final Ship Assessment

> ## NOT READY TO SHIP

**Current Status: 🔴 Blocked** — **1 open Blocker (F-53, release engineering)**, **3 open Important
(F-54 owner-action, F-105 accessibility product half, F-78 Phase 2)** plus F-51 accepted, **0 open
Minor**, and F-101 fixed-in-code pending device verification. F-53 is not a code defect: signing is broken, so no
device build, device QA, or receipt-witness validation can happen until the owner clears it.

> **Re-reconciled on 2026-10-21 (Round 21 close) — and the divergence Round 19 predicted happened
> exactly as predicted.** This block still read **2 open Important** and **8 open Minor** after Round
> 21 closed five findings (F-46 residual, F-98, F-106, F-107, F-112), half-closed F-105 and left
> F-47/F-48/F-49 fixed-but-unaudited. Three changes above: the Minor count drops **8 → 3** because
> Round 21's closures landed; **F-78** is named as the third open Important because it has been one
> since Round 15 and neither block ever counted it; and **F-113** gets its own line because "ungraded"
> is not a severity and it kept falling out of both counts. The rule from Round 19 stands and is now
> twice-proven: **when these two blocks diverge, the Metadata row is the one being maintained** — so
> reconcile this block *from* it at every round close rather than editing them independently.

> ✅ **Repository state, as of Round 22 close: committed, and the audited state equals the committed
> state.** The tree was committed at `82cb510`, reopened by Round 21 with 21 entries / 1,375
> insertions, and committed again by Round 22 in seven commits grouped by finding. The unreviewed
> delta that made the previous wording a blocker on any ship claim has been read; what remains open
> is release engineering and product work, not unexamined code.

### Round 22 update — the answer to "is this ready?"

**No, and the three reasons are now the only reasons — which is the first time that has been true.**
Round 22 read the 298-insertion fix delta Round 21 handed over as its first and non-negotiable item,
and the delta held: no Blocker, and no defect in the policy or receipt-ledger fixes themselves. Every
claim those fixes' comments made was checked at the call site, and all of them were accurate.

**What it found instead, and the pattern is worth naming.** The two findings are both in the F-46
app-target fix, and **F-114 is a correct mechanism with a false report** — the receipt reset was moved
after the SwiftData transaction on purpose and that ordering is right, but it shared the transactional
`catch`, so a failing ledger reset told the person *"Changes in that phase were rolled back, so you
can retry the privacy reset safely"* at a point where their search history, token holdings, music
library, playlists, NFT data and tags were already erased. Retrying really was safe; only the sentence
was false. **It got through for the reason this audit has now recorded four times** (F-92, F-99,
F-108): the recording double was given a `failure` property that no test ever set, so the failure path
had no coverage at all. **That makes five consecutive rounds in which the previous round's fixes
contained a real defect** — and the second in which the defect was in the *reporting* of a mechanism
that was itself sound.

**What is now closed.** F-47, F-48, F-49 and F-113 are read and resolved; the Minor column is empty
for the first time since Round 10. The tree is committed in seven commits grouped by finding, so the
audited state equals the committed state and the "fixes live uncommitted while the index holds the
pre-fix code" condition — flagged in Rounds 15, 16, 18, 20 and 21 — is closed again. `BuildProject`
clean for testing; lint **0 violations in 866 files**; PolicyCore 10/10, ReceiptStorage 182/182,
OperatorsFeature 110/110, AccountsFeature 18/18 on the host, app plan 75/75 across the three affected
suites. Non-tautology proven by restoring pre-fix source for both behavioural groups rather than
argued.

**What is still open, and none of it is unexamined code.** **F-53** remains the single largest item
and is release engineering: no signed build can be produced, which transitively blocks device QA,
FoundationModels telemetry, the receipt-witness smoke test (F-54) and hardware verification of the
F-101 keystore re-wrap. **F-105's product half** is the one open Important with product work in it —
5 accessibility failures across 7 tests, measured twice, and no round has attempted it yet. **F-78**
is deferred to Phase 2 by decision.

**The honest summary.** The branch is in the best state this audit has recorded: committed, with no
unreviewed delta, no open Blocker in any first-party package, and an empty Minor column. It is still
not shippable, and what stands in the way is a signing account, a CloudKit container and some
accessibility product work — not code nobody has read.

### Round 21 update — the answer to "is this ready?"

**No, and for the first time in several rounds the reason is not only F-53.** Round 21 worked the
open-findings backlog rather than reading new surface, and it closed five findings — but it closed
them by *verifying anchors in live code first*, which caught **three of this document's own claims
being stale**, and it ended by putting the repository back into the one state this audit has
repeatedly called the highest-risk position.

**What improved, and it is real.** **F-107** closed by disproving the reason it had been left open
across two rounds: normalizing the receipt account-address write path was deferred because it "would
change what future receipts hash", and it does not — `AuralisEthereumAddress` trims, lowercases and
re-emits `"0x" + 40hex`, so for every shape a writer actually produces the result is byte-identical
to the previous `trimmed.lowercased()`. Proven by reverting: exactly the 2 defect tests fail, both
controls hold. **F-46's residual** closed with no package change at all — the app target's fourth
receipt-reset implementation is *deleted* rather than reconciled and now calls the ledger's own
locked `resetAll()`. **F-112** closed via a file split that delivered **18 host tests that could not
run at all before**. **F-98** and **F-106** closed as recorded decisions, each pinned by a test or a
second measurement rather than by a comment. Gate: lint **0 violations in 866 files**; ReceiptStorage
**182/182**, OperatorsFeature **110/110**, AccountsFeature **18/18** (host), app plan **24/24** across
the two privacy suites; `build-for-testing` clean for `Auralis-Full`.

**What did not improve: the accessibility product half.** A fresh `Auralis-Full` run reproduced the
Round 19 position exactly — **22 executed / 2 skipped / 8 failed** — which is the first time those
counts are measured twice rather than asserted once. The **harness class is fixed** (and its cause was
not the overflow lookup everyone assumed: `MainTabView` gated only 6 of 11 tabs on `showsInTabBar`,
so the tab bar could never narrow). But `testNFT` moved *out* of the harness class and *into* the
product class, so **5 product failures became 5**, now spread over 7 tests. F-105's open half is
untouched product work and no round has yet attempted it.

**What is worse than when the round opened, and it is the thing to act on.** The branch was fully
committed at `82cb510`; it is now **21 entries / 1,375 insertions / 553 deletions** of uncommitted
work, and that delta contains **two agents' changes mixed together**. **298 of those insertions —
F-47/F-48/F-49 in `ActionPolicyGate`/`StandingToolPolicy` and the F-113 follow-up in
`SwiftDataReceiptStore` — were written by a concurrent agent and have been read by nobody.** Round 21
explicitly did not claim them. This is verbatim the unreviewed-fix-delta position that produced a
**Blocker in four consecutive rounds (13, 14, 15, 16)**, and it now sits in the policy gate and the
receipt ledger — the two surfaces where this audit's Blockers have historically lived. Round 22's
first and non-negotiable item is reading that delta.

**The honest summary.** The reviewed code remains in good shape and the backlog genuinely shrank.
What stands between this branch and a ship decision is unchanged in shape — F-53's signing block, the
F-54 owner action, and accessibility product work — with one addition that is nobody's to defer: the
tree must be committed and its unreviewed half audited before any of those numbers mean anything.

### Round 20 update — the answer to "is this ready?"

**No — and the reason is the same two items it has been for several rounds, not anything Round 20
found.** The round's own findings are real but small: one Important and two Minor, all three fixed,
all three in code that nine consecutive round plans had carried as unread. Nothing it found is a
Blocker, and nothing it found changes the shape of the gate.

**What the evidence supports.** The staged index was measured **byte-identical to Round 19** — 307
files / 16,565 insertions / 1,223 deletions, zero untracked — so there was no unreviewed fix-delta,
the condition that produced a Blocker in four consecutive rounds. `BuildProject` clean. Lint **0
violations in 864 files**. `WalletConnectionInteractionTests` **11/11**, including a new regression
test whose non-tautology was proven by restoring the pre-fix body and observing **10/11 with exactly
that test failing**. Four separate claims that prior rounds had taken on trust were verified against
their call sites and recorded as PASS rather than re-derived next round: the background-task
registration, `ContextService`'s single-flight generation guard, ritual-notification authorization
timing, and the UI-test fixtures' inability to reach the real store.

**What is still open, and why it is not code.** **F-53 remains the single largest item and it is
release engineering, not a defect:** no signed build of this app can be produced at all, which
transitively blocks the physical-device pass, QA sign-off, FoundationModels telemetry, the
receipt-witness smoke test (F-54), and — since Round 18 — hardware verification of the F-101 keystore
re-wrap, which is custody code touching the only copy of a seed. **F-105/F-106 (accessibility) is the
one open Important with product work in it**, and it is measured and failing rather than unmeasured:
three product classes across six tests plus one harness class. Round 20 touched no UI and so moved it
neither way.

**The honest summary.** The code in the reviewed scope is in good shape, and the trend across rounds
supports that: Round 20 read 5,070 lines of app-target source that had never been read line-by-line
and found one Important, which is a low yield for first-read code in a wallet-adjacent surface.
Two things temper it. First, **F-108 is the third consecutive confirmation that this codebase's real
risk is untested paths rather than wrong-looking code** — the defect was invisible to the suite
because `sessionDeleted` had no test anywhere in the repo, and the two guards before it (F-92, F-99)
failed the same way. Second, **~8,900 lines remain unread at depth**, most of it tests, and this
document has now mis-described that backlog in two consecutive rounds — mis-enumerated in Round 19,
mis-sized by ~4× in Round 20. The branch is not ready to ship, but what stands between it and a ship
decision is one owner-action Blocker, one accessibility Important, and a shrinking read-backlog —
not an unstable codebase.

### Round 19 update — the answer to "is this ready?"

**No, and this round's contribution is that it caught the document describing a run that did not
reproduce.** Round 19 was a bookkeeping and verification round: it did not read a new package, and the
code it did read came out clean. What it did do is re-run the thing the previous round's headline
rested on, and the numbers came back different.

**What the evidence supports.** `AlchemyProposalSimulator`, `SocialInviteMint`, `SocialInviteCoding`
and `SocialInviteExchangeModel` were read at depth — 746 lines off the "unread at depth" list — and
produced **no finding of any grade**. The invite path in particular is the shape this document keeps
asking for: `decode` validates topic and nonce against the exact hex shape `mint` emits and rejects an
implausible `expiresAt` *before* anything is persisted or subscribed, and the "joined but unverified"
state is modelled as its own case rather than collapsed into `.failed`. `SocialCore` re-ran at
**185 tests in 13 suites, passed**. The staged tree is **307 files / 16,565 insertions / 1,223
deletions** with zero untracked files.

**What it does not support — three things, stated plainly:**

1. **`Auralis-Full` is not green, and the prior record of it was optimistic.** The re-run reports
   **952 tests: 940 passed, 8 failed, 4 skipped** — not `TEST SUCCEEDED`. The 18 accessibility audits
   come out **8 passed / 8 failed / 2 skipped**, where Round 18 recorded 13 passed / 7 failed with
   0 skips. More failures, and two audits now skipped that were previously asserted to run. Nothing in
   the staged tree obviously explains the drift, which is itself the point: the number was recorded
   once and not re-derived.
2. **Accessibility findings keyed to element names do not survive a re-run.** The two empty-frame
   `StaticText` failures named *"Preview"* and *"Library"* in Round 18 and name *"1 scoped NFT"* in
   Round 19 — same failure class, different element, same test. Any remediation scoped to a named
   element would have been scoped to the wrong thing. B5–B9 stay ❌ measured-and-failing.
3. **The "unread at depth" residual was mis-enumerated and is only partly retired.** It names twelve
   app-target files, not nine; four were read this round. The remaining eight, the ~40 smaller files,
   the `MissionControlFeature`/`NFTLibraryFeature`/`ArtifactCore` remainders and ~5,600 lines of test
   code are still unread, and that is Round 20's first item.

**The ship gate is unchanged and still belongs to the owner.** F-53 blocks every signed build, and
through it the physical-device pass, QA sign-off, FoundationModels telemetry, and F-54's
receipt-witness smoke test. The tree is still uncommitted — 307 files staged and ready, which is the
closest this branch has been to a commit, but it is not one.

### Round 18 update — the answer to "is this ready?"

**No — but the code read this round is high quality, and the reasons it is not ready have not changed
category since Round 7.** Two things are worth separating, because conflating them is how a green
round turns into a claim it cannot support.

**What the evidence supports.** The unstaged delta is careful, well-reasoned work. The three changes
with the most security surface were each verified against their call sites rather than taken on their
comments, and each held: the new `AutopilotAuthorizer` confirmation floor closes a real hole (an
`.observe`-labelled `signMessage` step previously returned `.autopilot`, producing a signature with no
confirmation) and it does so with `minimumImpact` rather than `defaultImpact`, so read-only plugin
steps are not over-gated into the approval inbox — the exact inversion this codebase has gotten wrong
before. The `ProposalSimulation` `payload.*` aliases match `PolicyActionPayload.Key` key-for-key, and
the *omission* of `payload.token`/`payload.owner` is load-bearing and correct: it keeps an
`approveSpending` at `.notApplicable` rather than dry-running a no-op and telling the user "succeeds,
no asset changes" about calldata that was never simulated. The keystore work is the strongest in the
set — a fail-closed/fail-open predicate twin with both halves wired, a presence probe that cannot
trigger a biometric prompt, a creation lock held across no suspension point, and a delete path that
refuses to claim an irreversible removal it did not perform. Build clean, lint 0/863, 12 package
suites and 991 tests green, 677/677 on the app plan's Swift Testing half.

**What it does not support.** Three things, stated plainly:

1. **Round 18 did not read all of the delta it scoped itself to.** Roughly 1,100 lines of unstaged
   app-target source — relay assembly and inbound, wallet service/view/derivation, `ModeState`,
   envelope cipher — were not read at audit depth. These are live custody and relay paths and the
   relay flag is now `YES`. Eight of the last ten rounds found something in the area they had not yet
   read, and three found it specifically in unstaged code. That base rate is the argument.
2. **F-99 is a reminder that green suites and read code are different claims.** A guard protecting
   the "which one" half of every attribution label had no test at all, and deleting it left two full
   package suites green. It was found by a mechanical technique, not by reading harder. Four more
   guards of that shape were found in Round 17. There is no reason to believe the count is now zero.
3. **F-57 is finally deterministic and still unexplained.** It fails the same way in isolation, at an
   assertion that has probably never run before, and the two candidate causes differ in kind — a test
   harness limit, or an operator that genuinely is not registered. Until that is discriminated, the
   Operators console has one failing smoke test and no verdict on whether the product or the test is
   wrong.

**The ship gate is unchanged and still belongs to the owner.** F-53 blocks every signed build, and
through it the physical-device pass, QA sign-off, FoundationModels telemetry, and F-54's
receipt-witness smoke test. The Release secrets are still absent. The tree is still uncommitted,
though less so than before — and the `SocialCore`/`OperatorsFeature` commit this round confirmed is
the kind of progress that actually retires plan items.

**Phase 1 code review froze 2026-10-07 (Round 13).** Every open finding is now an owner action or an
environment blocker; none is code. See *Round 13 update — the Phase 1 code freeze* below for what the
freeze does and does not cover.

### Round 13 update — the Phase 1 code freeze

**Phase 1 code review is closed as of 2026-10-07.** This is a freeze of the *review*, not a ship
decision — the two are separate and conflating them is how a freeze turns into a claim it cannot
support.

**What is frozen.** The Phase 0–1 code surface. All 28 of Round 13's findings are resolved, across
the three Blockers, the thirteen Important, and the twelve category-4/5 items the owner directed
closed in a follow-on pass. No finding from any round is deferred into the freeze. From here,
anything discovered triages into **Phase 2 / backlog** rather than reopening Phase 1 — including
the cross-cutting seams listed as Loop 2 item 1, which are now Phase 2 entry work rather than
Phase 1 debt.

**The evidence it rests on:** app plan 771 passed / 0 failed (unchanged from baseline); 16 package
suites green, 1,037 tests; lint 0 violations in 857 files; CI lane coverage verified for every
package this round touched; repo-state checks clean, no scratch files, `^[AMR]D` empty.

**What is explicitly *not* frozen, and why that is the honest line.** Three things that no amount of
code review can close, all of which gate the Phase 1 → Phase 2 entry criteria in
`Phase-2-Kickoff.md`:

- **F-53.** No signed build of this app can be produced at all, which transitively blocks the
  physical-device pass, QA sign-off, FoundationModels telemetry, and F-54's receipt-witness smoke
  test. `MC-Device-010` (BGTaskScheduler firing on hardware) and `MC-Device-011` (Secure Enclave
  receipt signing) are named ship blockers and remain unverified.
- **F-57.** 18 accessibility UI tests have never executed, so B5–B9 cannot come off ⬜ on their
  existence alone.
- **The working tree is uncommitted** — 439 entries, including every fix in this round. A freeze
  that lives only in a working tree is not a freeze. Committing it is the owner's action, and needs
  an explicit pathspec (see memory `phased-build-out-has-a-large-preexisting-index`).

**Confidence in the freeze itself, stated plainly.** Round 13 found three Blockers in packages that
four earlier rounds had already read, two of them in the human-trust surface and the receipt chain.
That is the fifth consecutive round where "this package was read" proved weaker evidence than it
sounded, and it is the main reason to hold the assessment at NOT READY TO SHIP rather than letting a
clean round read as a clean codebase. What argues *for* freezing anyway: every one of those fixes
was local, none required architectural rework, and the defects were of a consistent and now
well-understood shape — a mechanism that exists to state the truth failing to state it. That is a
late-stage hardening profile, not a foundation problem. Continuing to review statically has
reached diminishing returns; Phase 2 will exercise this architecture harder than another read will.

### Round 10 update — the answer to "is this ready?"

**No — and this round is the first in four to move the answer *backwards*, which is the most useful
thing in it.**

Round 9 closed with "no known defect is open" and a plan whose engineering work was essentially
verification. Round 10 read four packages at the owner's direction and found **two Blockers** in
code that every prior round counted as read. Both turned an ordinary, non-exotic event — *upgrading
the app*, *restoring to a new device* — into a permanently invalid audit trail whose only recovery
was deleting the history the user was trying to keep. Neither was exotic to trigger and neither
required an attacker.

**What that says about the audit, not just the code.** "All first-party code has been read" was true
by file and false by depth. `ReceiptSignerFactory` was read in Round 1 — F-1 came out of it — but no
round had asked what `verifyIntegrity()` *does with* a signature, or what `exportAll()` does with that
verdict. The lesson for Round 11 is written into the fresh-session checklist: a large uncommitted diff
in a package is unread scope regardless of what the Review Ledger says.

**Two process facts worth keeping.** First, package-green was not app-green: all four package suites
passed while an app-hosted assertion still failed, and that assertion turned out to encode the exact
policy F-39 exists to remove. Second, the verification *policy* was the defect, not the cryptography —
the signing design, the ledger lock, and the address normalization in that work are good, which is
why the fix reshaped the verdict rather than the crypto.

**Where it leaves the gate.** The two owner actions from Round 7 are unchanged and still the critical
path. Added to them: **F-44 is open**, and it is the third instance of the shape the two Blockers
shared, so it should be closed before this area is called done. **`ReceiptsCore` is now load-bearing
and unread** — the F-40 fix deliberately kept its export wire format frozen because the package was
out of scope. And **F-47** deserves its six lines: it guards a defect that has already shipped once
(F-50), where every receipt written in Assist or Operate was silently stamped "Observe".

Honest summary: the engineering position is better than it was — two real Blockers are gone and the
receipt ledger now survives the two events that would have broken it — but the *audit* position is
less complete than Round 9 believed, and one Important is open.

### Round 9 update — the answer to "is this ready?"

**No, and still for the same two owner actions — but the engineering side of this audit is now
finished. There is no unread first-party code on the branch.**

Round 9 entered the last three unread areas: app-target `Assemblies`, `Aura/Receipts`, and the two
RuntimeKit files Round 6 had only skimmed. It found **two Importants**, both fixed, and both of a
kind that no amount of additional testing would have surfaced — because in both cases everything
built and every test passed.

**F-35 — every background refresh leaked an entire runtime host.** `runInBackground()` opened a
fresh `ModelContainer` on each invocation, and `RuntimeAssembly.sharedHost` memoizes on container
identity with no eviction, so each hourly wake constructed and permanently retained another
`RuntimeHost` — event bus, scheduling engine, tool registry, lease registry, and open connections
to two SwiftData stores. This is the thing Rounds 5, 6, and 7 each wrote down as "follow F-23 to
its source" and each deferred. The source was worse than the duplication F-23 tolerated: not two
hosts, but unbounded growth, with `flushEventCheckpoints()` walking the whole graveyard on every
backgrounding and each new host re-seeding standing authority during exactly the window F-27
identified as dangerous.

**F-38 — a commit would have deleted three files and added nothing back.** The `MusicApp` rename
was half-recorded: two files staged as proper renames, three left as staged-deletion-plus-untracked.
Nothing in the working tree shows this, because synchronized folders take target membership from
the filesystem — it builds, it tests green, and the damage appears only in a fresh clone. It also
slipped past this document's own guard: F-2's `^[AMR]D` check has run clean every round and
correctly so, because this pattern is `D ` on one path and `??` on another.

**And that check found something worse about the audit itself.** Five test files *this audit wrote*
had never been `git add`ed — including `TrustedUIA11yIDMirrorTests.swift`, which **is** F-18's
entire fix, and `RequestThrottlerTests.swift`, which is F-20's proof. Both findings have been
recorded as Resolved for five rounds. Committing the tree as it stood would have shipped their
fixes with no proofs and silently reopened them. Now tracked; zero untracked files remain under
`AuralisTests/`.

**The A5 sweep came back clean, and that is a real result.** Four rounds have now swept for the
actor-reentrancy pattern deliberately. `RitualCoordinator` routes every shared-session write
through the store-side `mutate` closure and claims runs with `beginRun`/`finishRun`;
`AutopilotStepExecutor` is a per-run `struct` of `let`s with no shared mutable state. The count
stands at four real instances, none new since F-27.

**One honest note about method.** Three consecutive full-plan runs reported failures that were not
real — a stale `Auralis.swiftmodule` had the test bundle linking a pre-fix implementation, so it
reported precisely the tests that fail pre-fix, on source that provably had the fix. Hand-deleting
the module produced a different false signal. Only a clean build gave a true answer: **590 tests,
0 failures, 0 skips.** And before that, one of my own new tests was wrong — it opened the real
on-disk store and was unsafe under the plan's parallel clones. Rewriting it to inject an in-memory
container also made it assert the stronger property (opens == 1). Both are in the record because a
future round will hit them again.

**Where the evidence stands after nine rounds.** 611 package tests; **590 app tests, 0 failures, 0
skips** from a clean build; Release compiles clean; lint 0/835 strict at a pinned version; Debug
clean. Every named package, both runtime packages, the artifact packages, the app target, and the
app test plan are read. All ten Round 0 questions are closed. **0 Blockers, 0 Importants, 0
Minors** across nine rounds; seven Observations remain open by choice.

**Why it is still NOT READY TO SHIP.** Two owner actions, unchanged since Round 7:

1. **The Release secrets are not on this machine**, so no genuine Release artifact exists.
2. **The tree is uncommitted** (~498 entries), so the audited state is not the shippable state and
   no PR can be raised. Rounds 8 and 9 at least made committing *safe* — before F-38 and the
   untracked-test fixes, a commit would have destroyed files and two findings' proofs.

Beyond those, what remains is verification the owner has to perform (device QA, archive signing,
first green CI run) and one genuine review gap: **accessibility B5–B9 outside TrustedUIKit**. That
is the honest remaining answer to "is this ready" — not unread code any more, but unfinished
verification.

### Round 8 update — the answer to "is this ready?"

**No — and the two reasons are the same two the owner was handed after Round 7. Neither is
engineering work. Round 8 did not find anything that changes that, and it did find three things
worth fixing first.**

The owner asked whether the 23 named packages are high quality and ready to ship. On the evidence
of eight rounds: **the code in those packages is high quality.** All 23 are line-read, all 23 pass,
603 tests, zero lint violations, zero open Blockers, Importants, or Minors anywhere on the branch.
Round 8 read the two corners no round had opened — the artifact packages, and the operator packages
at more than sweep depth — and what it found there were three Minors, not a defect of design.

**But "high quality" and "ready to ship" are still different claims, and the gap is not code.**

**What Round 8 found, and why the pattern is the interesting part.** Both code findings are the
same shape, and it is a shape this codebase is otherwise very good at: *a rule the project already
states, applied in one place and not the other.*

- **F-32.** `ArtifactSchema` says, in its own doc comment, that a record it cannot interpret must
  fail closed "rather than guessing". That rule was enforced on the way *in* and not on the way
  *out*, so the store coerced unknown artifact states to `.draft` — the most permissive state
  available — and unknown types to `.doc`. A newer build's record would have come back looking like
  ordinary unreviewed work that a person could approve and export.
- **F-33.** `addVersion` already wrapped its write in `do/catch { rollback() }`. Five sibling
  writers did not, and `@ModelActor`'s context is long-lived — so a failed approval stayed pending
  and was committed by the next unrelated save. The app would tell a person their approval failed,
  and then record it anyway.
- **F-34** is the same shape one level up: the audit has measured lint with `--strict` at a pinned
  binary since Round 4, while CI installed an unpinned SwiftLint and ran it unstrict. The gate was
  not enforcing what the document said was enforced. I found it only because a stale 0.47.0 on this
  machine reported 34 violations where the pinned 0.63.2 reports 0 — a discrepancy that was itself
  the finding.

None is a Blocker. All three are fixed, each with a test or a verified command behind it, and all
eight new tests were proven to fail against the pre-fix source.

**Q-7 is closed, and the honest answer is that the hypothesis was wrong.** The `PrimaryStoreSchema`
change that has carried a Blocker label since Round 0 is a trailing comma. Checking it properly
meant diffing every `@Model` file on the branch, not just that one — done, and there is no
migration missing. That was the last unexamined persistence risk.

**Where the evidence stands after eight rounds.** 603 tests across the named packages; the app plan
green with 0 failures and 0 skips; 1,281 package tests at the branch level; Release compiles clean;
lint 0/833 strict at a now-pinned version; every named package, both runtime packages, the artifact
packages, and the app test plan covered. **0 Blockers, 0 Importants, 0 Minors.** Six Observations
remain open by choice.

**Why it is still NOT READY TO SHIP.** Unchanged from Round 7, and both items belong to the owner:

1. **The Release secrets are not on this machine.** No genuine Release artifact can be produced.
2. **The working tree is uncommitted** (~494 entries), so the audited state is not the shippable
   state and no PR can be raised.

Plus one thing that is still an auditor's job and is now the largest remaining review gap:
**`Aura/Receipts`, `Assemblies`, and the back half of RuntimeKit have never been read.** They sit
outside the 23 packages this round was scoped to. `Assemblies` has already produced one defect
(F-31), and every round that has opened an unread area has found something in it — eight for eight,
including this one. That is the strongest reason not to call the *branch* ready yet, and it says
nothing against the packages the owner actually asked about.

### Round 7 update — the answer to "is this ready?"

**Not yet — but for the first time the remaining reasons are not engineering work. They are two
owner actions.**

Round 7 spent no time reading code. It did the two things six rounds had deferred: run the
app-target test plan, and build the Release configuration. Both had been recorded as blocked. Both
turned out to be doable, and both were hiding something.

**The app-test blocker was a misdiagnosis that survived six rounds.** Every round carried "blocked
by the Xcode-beta app-hosted test crash". It did not reproduce. The real obstacle was that the app
targets **iOS 26.0**, so every iOS 18.x simulator is refused with a deployment-target mismatch —
which reads like a toolchain failure if you don't check the destination's runtime. On iOS 26.5 the
plan runs start to finish.

**And the first run immediately caught a real defect (F-31).** Two app files, both new on this
branch, import `OperatorsFeature` without the app target declaring it; it links only transitively.
The day an intermediate package drops that dependency, the app stops compiling for a reason
unrelated to whatever was being edited. It was also a **red test in `Auralis-Full`, the plan CI
runs** — this branch could not have gone green on a PR. The test that catches it was already
written. It had simply never been allowed to run. That is the strongest argument in this document
for why "the suite is green" and "the suite has executed" are different claims.

**Release had never been built, and it fails here — correctly.** `ValidateReleaseSecrets.sh` refuses
it: this machine has 1 of 3 secrets. That refusal *is* the gate working, and it is the reason Release
had never been built. With stand-in values the build is **0 errors, 0 warnings**, so the compile is
sound. Reviewing the gate itself found two defects in it: it validated **two of three** secrets
(**F-30** — a Release could ship with WalletConnect silently unavailable), and the validation script
was **shipping inside the app bundle** in both configurations (**F-29**, via Xcode 16 synchronized
folders, which include anything in a target's directory by default). Both fixed and verified.

**I also corrected one of my own mid-round conclusions.** I flagged that `SWIFT_OPTIMIZATION_LEVEL`
is absent from Release's `-showBuildSettings` and inferred a possible unoptimized ship. The real
build log disproves it — `-O` and `-whole-module-optimization`, 212 and 210 invocations. The dump
does not list inherited defaults. Left in the record because reading it alone supports the wrong
conclusion.

**Where the evidence now stands.** 1,281 package tests. **580/580 app-target tests.** Release builds
clean. Lint 0/831. Debug builds clean. Every named package, both runtime packages, and the app test
plan are covered. **0 Blockers, 0 Importants, 0 Minors** across seven rounds; six Observations remain
open by choice.

**Why it is still NOT READY TO SHIP.** Two items, both the owner's:

1. **The Release secrets are not on this machine.** `AURALIS_HELIUS_API_KEY` and
   `AURALIS_WALLETCONNECT_PROJECT_ID` are absent, so no genuine Release artifact can be produced —
   and after F-30, the gate now correctly refuses on the second one too.
2. **The working tree is uncommitted** (~493 entries), so the audited state is not the shippable
   state and no PR can be raised.

Everything an auditor can settle by reading or running has been settled. What is left needs
credentials and a commit.

### Round 6 update — the answer to "is this ready?"

**No — but the reason has changed category. Every line of the branch's code has now been read; what
is missing is *execution evidence*, not review.**

Round 6 audited the governance kernel, the last T0 area at ⬜ and the largest unread surface on the
branch. It found **one Blocker**, fixed it, and closed the review side of the audit.

**F-27 — the authority registry refused grants it was in the middle of loading.**
`CapabilityLeaseRegistry` marked itself hydrated *before* reading the store, so every caller
arriving during that read queried an empty lease table. The registry fails closed, so this produced
refusals rather than leaks — governed runs blocked with "Missing active capability lease", receipted
as **authority** refusals, for grants sitting in the store. A grant taken in the same window was
persisted to disk and erased from memory. Eight concurrent first callers: **seven refused**. This is
reachable on any cold start where two governed runs overlap, which is exactly when standing routine
authority is being re-seeded.

**The pattern, now four deep.** F-1, F-14, F-20, F-27 — the same actor-reentrancy shape in four
unrelated files. Three rounds have now swept for it deliberately. What makes F-27 the most
instructive: the flag *looked* like reentrancy protection. Setting `didHydrate = true` before the
await does prevent a duplicate read; it just hands the second caller an empty registry instead. The
codebase's own correct idiom — a cached `Task` whose **body** installs the result — was already in
use in three other places, including `RuntimeHost.bootstrap()` fifty lines away in the same package.

**What six rounds of evidence actually support.** The kernel is well-built, and the sweep says so
more credibly than a clean bill would: one defect in 13,866 lines, in a file whose neighbours all
handle the same hazard correctly. `StandardChecks` fails closed at every decision and documents an
earlier fail-*open* it fixed. `CorrelationGate` forwards cancellation for a reason it takes a
paragraph to justify and is right about. `GovernedToolPipeline`'s "nothing executes outside this
pipeline" claim survives inspection, including its approval point-of-no-return. The recurring
weakness is not judgement — it is that correct-looking concurrency shortcuts keep surviving review
until someone writes the concurrent test.

**The finding backlog is now empty of everything actionable.** Round 6 also closed the four Minors
carried since Rounds 2–4 (F-3, F-8, F-9, F-11). Across six rounds: **0 Blockers, 0 Importants,
0 Minors open.** The six remaining WARNs are all Observations, each open by choice. F-8 is worth
singling out because it was closed with a *measurement* rather than a decision — instrumenting the
snapshot comparison showed all nine baselines differ by 0.000000%, so the 2% budget had never been
absorbing anything, and the replacement was derived from that number instead of picked.

**Why it is still NOT READY TO SHIP.** No Blockers, no Importants, no Minors, nothing unread. Three
things remain, and none of them are opinions:

1. **No app-target test has ever executed.** ~80 files, across six rounds, including two this audit
   wrote. The app compiles; the blocker is the Xcode beta's app-hosted test crash. Until one green
   run exists, the app target's behaviour is unverified by anything but review.
2. **Release has never been built or reviewed line-by-line.** Only Debug.
3. **The tree is uncommitted** — 493 working-tree entries — so the audited state is still not the
   shipped state, and no PR can be raised.

The defect trend across six rounds is Blocker → Blocker → none → 2 Blockers → Important → Blocker,
and the last three were each found by entering an area no prior round had read. There is no longer
such an area. That is the strongest statement this audit can make, and it is still not the same
statement as "ready".

### Round 5 update

**No — and the honest reason has narrowed to one sentence: the governance kernel has still never
been read.**

Round 5 closed the last of the 23 named packages the owner asked about. All of them are now
line-read, all of them pass, all of them lint clean. **1,000 tests green** across the named packages
plus RuntimeKit and MissionControlFeature; SwiftLint `--strict` reports **0 violations in 831
files**; the app builds Debug with 0 errors — the first app build recorded in this audit.

**What Round 5 found.** One Important and two Minors, all fixed, all in the same theme: a durable
store that nobody had bounded, and two readers that disagreed with their own package.

- **F-24 — advisory recommendations grew as N².** The improvement-recommendation ID embeds its
  evidence deliberately (so a new run re-proposes rather than overwriting a reviewed row), but the
  evidence was every graded run the operator had ever had, graded runs are never pruned, and nothing
  deleted a row. Every Mission Control report-card refresh after a new run wrote up to four larger
  rows. ~74 MB of durable bytes at 1,000 graded runs for one operator — and the card rendered every
  retired row forever, burying the actionable ones under a growing wall of "Superseded".
- **F-25 / F-26** — one playbook row this build cannot decode took down the whole operator library
  including its own repair path; and `interventionRate` differed depending on whether the device had
  a SwiftData container.

**The A5 sweep is the result worth reporting even though it found nothing.** Round 4 escalated actor
reentrancy to a codebase-wide pattern after three separate hits. Round 5 enumerated every actor in
the 23 named packages and read each one that both holds mutable state and suspends: **no fourth
instance.** Two look-alikes were read and cleared with written reasons. That pattern is now closed
for the named packages — and correspondingly still wide open for the 120 files of RuntimeCore and
RuntimeKit, which is precisely where the concurrency actually lives.

**Why it is still NOT READY TO SHIP.** Not because of any open defect — there are none. Because:

1. **RuntimeCore and RuntimeKit (T0, 120 files) have never been read.** They are the governance
   kernel. Every round that opened an unread area found something in it, twice a Blocker. Two of the
   three A5 instances and both Round 4 Blockers came out of areas exactly like this one.
2. **No app-target test has executed in any round.** ~80 test files, including two this audit itself
   wrote (F-18's mirror test, Round 3's derivation tests). Round 5 proves the app compiles; the
   remaining obstacle is the beta's app-hosted test crash, not the code.
3. **Release has never been built or reviewed line-by-line**, and the tree is still uncommitted — so
   the audited state is not yet the shipped state.

The trend across five rounds is genuinely good: the defect rate is falling, the defects are getting
smaller (Blocker → Blocker → none → Blocker → Important), and the last two rounds found problems of
*growth and consistency* rather than of correctness or safety. But "ready to ship" cannot be claimed
for a branch whose central new subsystem is unread, and Round 4's evidence — two Blockers behind
fully green suites — is the direct argument against inferring quality from the parts already
checked.

### Round 4 update

**Not yet — but the remaining reason is unread scope, not open defects.** Every finding this audit
has ever raised is now resolved or accepted: **0 Blockers, 0 Importants**, 9 WARNs none of which
block. Lint and CI coverage are closed. 1026 package tests pass.

**What Round 4 found, and why it matters more than the numbers.** Two Blockers, both in areas no
prior round had read:

- **F-13 — Social v1 session takeover.** Any invite holder, including an ID that had never been
  admitted, could rewrite any participant's record, promote itself to owner, end the session, and
  eject the real owner. Three attacks were reproduced against the real projection. The code comment
  directly above the hole described it as the "session-takeover + hostile-participant" abuse gate.
- **F-23 — coordination state erased between hosts.** The background refresh opens its own
  `ModelContainer`, so it builds a second `RuntimeHost` with its own copies of the shared-session,
  ritual, and social stores over the same `UserDefaults` keys. Each one's writes erased the other's.
  Losing `RitualStore.lastRuns` makes an already-completed ritual **run again** — duplicate runs and
  duplicate notifications, plus silently dropped governance events.

Both sat behind fully green test suites. F-13's package was one CI never ran. Neither would have been
caught by any amount of additional testing of the kind that already existed.

**The single most useful structural outcome.** Before this round, SwiftLint covered 4 of 27 source
roots — and because `included:` overrides path arguments, even running it explicitly against a
package silently re-linted only those four, reporting a reassuring 5 warnings. The true figure was
405 violations and 1 error. CI, similarly, ran tests for 14 of 23 named packages. Both gate lines
now genuinely bind: **0 lint violations across 830 files**, and every package with a test target has
a verified CI lane. Two of the thirteen added lanes needed `swift test` rather than `xcodebuild`,
which only surfaced because each was executed in its CI form before being written down.

**What is well-evidenced now.** 1026 tests across 25 packages, including the first-ever execution of
RuntimeCore, RuntimeKit, and AuralisShellCore. `ExternalLinkPolicy` closes every URL-spoofing vector
with a written argument for each one it deliberately leaves open. `StoredReceipt`'s 14 new columns
are all Optional, satisfying SwiftData lightweight migration, with legacy rows read through
`ReceiptSchema.legacyVersion`. Q2/Q9 across 1000 files: zero `fatalError`, `try!`, `as!`, `TODO`,
`FIXME`, `HACK`. NFTKit accepts https-only media URLs. `OperatorExecutor` enforces the artifact
schema on composed output, so an unbounded model response cannot bypass the length limit.

**Why it is still NOT READY TO SHIP.** Three reasons, none of which is an open defect:

1. **RuntimeCore (69 files) and RuntimeKit (51) have never been audited** — both T0, and the security
   spine. Their 560 tests now pass and run in CI, but F-13 is the standing proof that a green suite
   is not a read. The A5 reentrancy pattern has already failed in three separate files (F-1, F-14,
   F-20); sweep for it there first.
2. **No app-target suite has executed in any round** — 0 of ~80 files, across all four rounds,
   because app-hosted runs crash on this Xcode beta. That now includes
   `TrustedUIA11yIDMirrorTests` and Round 3's `InAppWalletDerivationTests`.
3. **The tree is uncommitted** — 400 working-tree entries, no PR. The audited state is still not a
   recorded state, and CI has not yet run with the new lanes.

**The base rate is the honest argument.** Four rounds have now read the policy/signing spine, wallet
custody, MusicFeature, and the named-package gaps — and found a Blocker in three of them, including
two in this round alone. Every one was a narrow, understandable slip in otherwise careful work. That
is exactly why the two unread T0 packages should be read before shipping rather than after.

---

### Rounds 1–2 assessment (kept for the record)

**Explanation.** The **code** reviewed in Round 1 is of high quality and, on the
evidence gathered, is close to shippable. The 23 packages build clean and 395 tests
pass across 19 of them. The policy and signing spine is genuinely well-built: the
crypto-scoped Observe boundary (ADR-010) is implemented correctly, wallet actions
cannot reach `StandingToolPolicy`'s `.allow` branch in any mode, impact/capability
agreement is enforced by a registered deterministic check, infinite ERC-20 approvals
are refused on *value* rather than spelling, the hand-rolled Keccak-256 under EIP-55
is pinned to reference vectors, Keychain material uses
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and fails closed on a locked
Keychain, and `ArchitectureBoundaryTests` now makes bypassing the governed path a
build failure. Round 1 found **one** substantive code defect (F-1) in 138 files, and
it is fixed and covered by a regression test proven to fail against the old code.

**Round 2 update.** F-2 is cleared (index and worktree now agree) and Round 2 audited
MusicFeature plus the app-target wallet and Social surfaces. It found a **second
Blocker** — `InAppWalletKeystore` silently produced an unrecoverable self-custodial
wallet when a Keychain write failed (**F-6**), which would have permanently lost any
funds sent to the address, with no error shown. Also an Important defect where ERC-20
approval calldata could encode a different amount than the user reviewed (**F-7**).
Both are fixed and the app builds clean. MusicFeature's snapshot baseline movement is
explained and legitimate — a real fix to host-dependent rasterization and unstable
PNG byte comparison.

**Why it is still not ready to ship:** no Blocker is open, but the evidence base is
uneven. F-6 was a funds-loss defect found in the *first* custody file read, and
`InAppWalletSigner` (293 L) and `InAppWalletDerivation` (112 L) — the other two
irreversible custody paths — have not been read at all. F-6's fix also has **no test**,
because the keystore is not currently injectable. `Aura/Receipts`, the `Assemblies`,
SwiftLint, and the `Auralis-Fast` plan remain unaudited/unrun, and the tree is still
uncommitted. Shipping now would rest on the assumption that the unread custody files
are cleaner than the one that was read, and Round 2 gave direct evidence against that
assumption.

**Coverage after two rounds.** Audited: the 23 named packages, MusicFeature, and 5 of
30 app-target wallet/Social files (the irreversible ones — custody, approval encoding,
envelope crypto), plus both `xcconfig` files. Validated: `BuildProject` clean,
513 package tests passing, 5 of 9 Round 0 questions resolved. **Not audited:**
`InAppWalletSigner`, `InAppWalletDerivation`, 25 other wallet/Social files,
`Aura/Receipts` (15), `Assemblies` (9), accessibility (B5–B9), SwiftLint, and the
`Auralis-Fast` plan. "Ready to ship" cannot be claimed for the branch as a whole on
Round 2 evidence — but the code that *has* been read is of high quality, and the two
Blockers found were both narrow, understandable slips in otherwise careful work.

### Conditions required for READY TO SHIP

Status may only become 🟢 Ready to Ship when **all** of the following hold:

- [ ] No unresolved **Blocker** findings remain.
- [ ] No unresolved **Important** findings remain (or each is documented and accepted
      in *Accepted risks at ship*).
- [ ] Relevant builds succeed.
- [ ] Relevant tests succeed.
- [ ] SwiftLint is clean.
- [ ] The final diff has been re-audited **after** all fixes were applied.
- [ ] The verification gate is fully checked and signed off.
- [ ] No known issue remains that would reasonably prevent production release.

Build, lint, and test success are **necessary evidence, not proof of correctness.** The
work is not ready merely because it compiles and the suite is green.
