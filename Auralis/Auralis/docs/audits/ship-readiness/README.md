# Ship Readiness Audit — `phased-build-out`

**Code Audit & Handoff Document.** This is not a one-shot diff review. It is the running record of an
iterative audit cycle: **Audit → Action Items → Re-Audit**, repeating until Current Status reaches
**Ready to Ship**.

> **Split from a single 5,658-line `SHIP_READINESS_AUDIT.md` on 2026-10-21, after Round 22.** Nothing
> was summarized or dropped — every section moved verbatim into the file named below. The old path
> `Auralis/Auralis/docs/audits/SHIP_READINESS_AUDIT.md` **no longer exists**; if a tool, a memory, or
> a handoff checklist offers it, that is a stale reference, not a second document.

---

## Reading order

A fresh auditor should read, in this order:

1. **[01-STATUS.md](01-STATUS.md)** — Metadata (including the live repository state), Summary, Scope
   of Changes, and the Iterative Audit Log table.
2. The newest row of the **Iterative Audit Log** in [01-STATUS.md](01-STATUS.md).
3. **[05-NEXT-ROUND-PLAN.md](05-NEXT-ROUND-PLAN.md)** — and continue from there.

Everything else is consulted as needed rather than read front to back.

## The files

| File | Contains | Lines |
| --- | --- | --- |
| **[01-STATUS.md](01-STATUS.md)** | Metadata · Summary · Scope of Changes · Iterative Audit Log | ~185 |
| **[02-FINDINGS.md](02-FINDINGS.md)** | Detailed Findings Checklist · Review Ledger · Findings Register | ~383 |
| **[03-VALIDATION.md](03-VALIDATION.md)** | Validation · Remaining Risks | ~311 |
| **[05-NEXT-ROUND-PLAN.md](05-NEXT-ROUND-PLAN.md)** | Next Round Plan · superseded plans | ~1,008 |
| **[06-SHIP-GATE.md](06-SHIP-GATE.md)** | Handoff & Verification Gate · Final Ship Assessment | ~878 |
| **[PROTOCOL.md](PROTOCOL.md)** | Audit Protocol — how a round is run | ~85 |

## Where the current status actually lives

⚠️ **Two blocks state the open-findings count, and they drift apart after almost every round that
closes findings.** The Metadata *Current Status* row in [01-STATUS.md](01-STATUS.md) is **the one
being maintained**; the verdict block in [06-SHIP-GATE.md](06-SHIP-GATE.md) is reconciled *from* it.
They disagreed for a full round after Round 18 and again after Round 21. If they disagree now,
Metadata is right.

When asked whether this audit is current, check four places first:

1. The Metadata *Current Status* row and *Live-state override* row ([01-STATUS.md](01-STATUS.md)).
2. The verdict block counts ([06-SHIP-GATE.md](06-SHIP-GATE.md)).
3. The Handoff & Verification Gate checkboxes ([06-SHIP-GATE.md](06-SHIP-GATE.md)) — one sat
   **checked** with a Round 6 parenthetical from Round 10 onward.
4. The *Accepted risks at ship* table ([06-SHIP-GATE.md](06-SHIP-GATE.md)) — it carried F-44 as "open
   and unassigned" for **ten** rounds after Round 11 fixed it.

## Appending a round

Entries are called **Round N**, not "Pass N" (Round 0 was scaffolding). Update these, in this order:

1. **[01-STATUS.md](01-STATUS.md)** — Metadata (`HEAD at last round`, `Rounds completed`,
   `Current Status`, the live-state row), then add a row to the **Iterative Audit Log** (newest
   first).
2. **[02-FINDINGS.md](02-FINDINGS.md)** — the **Findings Register** (`F-NN`, cumulative, never
   deleted; set `✅ Resolved (Round N)` and keep the original text), and the **Review Ledger** notes
   column, which is where durable carry-forward invariants go.
3. **[03-VALIDATION.md](03-VALIDATION.md)** — a "Round N" results block. Never claim validation that
   was not run.
4. **[01-STATUS.md](01-STATUS.md)** — a new Iterative Audit Log row **above** the previous round.
5. **[05-NEXT-ROUND-PLAN.md](05-NEXT-ROUND-PLAN.md)** — the previous plan moves to "Superseded plan
   for Round N" unless you are extending it.
6. **[06-SHIP-GATE.md](06-SHIP-GATE.md)** — the *Accepted risks at ship* table, and a "Round N
   update" under the Final Ship Assessment. **Reconcile the verdict counts from Metadata.**

**Do not start a new document.** This directory is the only ship-readiness audit for this branch, and
splitting a round across a new file is how the status blocks started disagreeing in the first place.

## Reusing the structure

The layout doubles as a reusable template for this codebase. To start a fresh audit, copy this
directory, clear the Iterative Audit Log / Findings Register, and reset every
checklist verdict to ⬜.
