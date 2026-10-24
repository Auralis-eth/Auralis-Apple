# Ship Readiness — Audit Protocol

> **Part of the `phased-build-out` ship-readiness audit, split across files in this directory.**
> Index and reading order: [README.md](README.md) ·
> [Status](01-STATUS.md) · [Findings](02-FINDINGS.md) · [Validation](03-VALIDATION.md) ·
> [Next Round Plan](05-NEXT-ROUND-PLAN.md) ·
> [Ship Gate](06-SHIP-GATE.md) · [Protocol](PROTOCOL.md)

---

**How a round is run, and the bar each finding has to clear.** Reference material; it does not
change round to round.

---

## Audit Protocol

### The cycle

1. **Re-measure scope.** `git diff --name-only main | wc -l`, `git status --porcelain`.
   If materially changed from Scope of Changes, update that section and say so.
2. **Select areas** from the Review Ledger, respecting tier order.
3. **Audit against the Detailed Findings Checklist.** Follow call sites, types,
   protocols, state flows, and dependencies *out of the diff* — a diff-local read is
   not sufficient to judge whether a change is actually correct.
4. **Record every substantive finding** in the Findings Register: verdict, severity,
   `file:line`, concrete failure scenario, and an actionable Swift fix snippet.
5. **Fix FAIL findings** (Blocker + Important) that can be safely addressed within the
   scope of this work. Add or update tests where the audit exposed untested behavior.
6. **Build and run the relevant tests.** Record actual commands and actual output in
   Validation.
7. **Re-audit the resulting diff, including the changes made during the audit itself.**
8. **Append a row** to the Iterative Audit Log with the round's evidence and outcome.
9. **Repeat** until the exit condition holds.

### Verdicts and severities

Two levels, deliberately distinct: a **checklist verdict** per item, and a **severity**
per finding.

| Checklist verdict | Meaning |
| --- | --- |
| ✅ **PASS** | Checked against this change set; no issue found. Positive evidence. |
| ⚠️ **WARN** | Non-blocking improvement. Ship-safe as-is. |
| ❌ **FAIL** | Blocking issue. Must be resolved or explicitly accepted before ship. |
| ⬜ | Not yet checked. |

| Finding severity | Definition | Maps to | Gate effect |
| --- | --- | --- | --- |
| **Blocker** | Must be fixed before shipping. | ❌ FAIL | Forces NOT READY TO SHIP. |
| **Important** | Should be fixed unless there is a documented, accepted reason. | ❌ FAIL | Forces NOT READY TO SHIP unless the reason is recorded here. |
| **Minor** | Worthwhile cleanup, not required for shipment. | ⚠️ WARN | May remain open at ship. |
| **Observation** | Future engineers should know; no change required. | ⚠️ WARN / ✅ PASS | None. |

### Working principles

- Be skeptical of the implementation without being unnecessarily destructive.
- Prefer simple, idiomatic Swift over clever abstractions.
- Do not invent requirements or redesign unrelated parts of the system.
- Do not paper over problems merely to make tests pass.
- When unsure whether something is safe, investigate the surrounding implementation
  before deciding.
- Avoid speculative refactoring and unrelated cleanup. Keep fixes focused on making
  *this* change safe, correct, maintainable, and shippable.
- A FAIL needs a concrete failure scenario (inputs/state → wrong output/crash).
  "This looks fragile" is a WARN or an Observation, not a Blocker.
- Never claim a review depth you did not perform, or validation you did not run.
- **Findings are never deleted.** When fixed, set Status to `Resolved (Round N)` and
  leave the original finding text intact so the reasoning survives.
- ✅ PASS is as valuable as ❌ FAIL. Recording what was checked and found sound is what
  makes the next round cheaper and the handoff trustworthy.

### Original criteria mapping

The 18 general review criteria are fully subsumed by the Detailed Findings Checklist:

| Criteria | Covered by |
| --- | --- |
| C1 correctness · C3 architecture · C5 concurrency · C6 memory · C9 API design | **A. Architecture & Swift Idioms** |
| C2 Swift/SwiftUI practice · C4 state & lifecycle · C10 accessibility · C11 localization | **B. UI & SwiftUX** |
| C7 error handling · C8 edge cases · C14 backwards compatibility · C15 dead code · C16 tests | **Q. Quality & Edge Cases** |
| C12 performance · C13 persistence/migration · C17 diagnostics · C18 ship discomfort | **S. Security & Performance** |

---
