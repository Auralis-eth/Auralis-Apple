# P0 Implementation Order Plan

This file is the practical implementation sequence for the current Phase 0 ticket set.

It is not a restatement of every raw JIRA dependency. It is the working order intended to get the project moving while respecting the dependency decisions already made in planning.

## Known Completed Foundations

- `P0-101A` Root navigation structure
- `P0-101B` Global Chrome UI first pass with fixed Observe presentation
- `P0-101D` Global error + empty-state patterns
- `P0-101E` Design system primitives
- `P0-202` Address validation + normalization
- `P0-201` Account model + persistence
- `P0-501` Receipt schema, append-only store, sanitization, export, and reset foundation
- `P0-601` Mode system Observe v0 (global mode-state ownership, chrome integration, receipt inclusion)
- `P0-204` Chain scope settings per account

## Current Status Note

- `P0-101A` is now closed for the current shell baseline: the app exposes Receipts as a root destination and routes receipt deep links through the live shell.
- `P0-101D` is implemented as the shared shell-status layer for first-run, provider failure, no-receipts, and empty-library states.
- `P0-202` is implemented as strict account-entry EVM address validation with deterministic trimming, normalization, and explicit ENS rejection until `P0-203`.
- `P0-202` is now explicitly a lowercase canonical `0x...` storage-and-copy contract for Phase 0; checksum display remains deferred.
- `P0-501` now includes explicit receipt fields for actor, mode, trigger, scope, summary, provenance, success/failure, and details, plus the Swift 6 actor-isolation cleanup needed to keep the store build-clean.
- `P0-601` is implemented; the chrome and context inspector read mode from the formal `modeState`, denied placeholder actions go through the policy gate seam, and receipts include `mode=Observe`.
- `P0-204` is implemented for the current Phase 0 baseline: per-account chain scope persists, drives the visible shell state, emits receipts, and triggers the active refresh hook.
- `P0-502` is now complete for the current shell/context/action slice: app launch, context builds, NFT refresh, account and chain changes, explorer opens, and the active copy action all emit receipts on the shared foundation.
- `P0-402` is now complete for the strengthened shell-facing context slice: context builds emit receipts and the mounted chrome plus inspector read the shared `ContextSnapshot` instead of parallel shell-state lookups.
- `P0-101B` has been re-validated as complete after the shell, mode, and chain remediation passes.
- `P0-401` is now in progress as a stronger schema-first slice: `ContextSnapshot` exists, the shell inspector reads it, provenance-bearing scope/freshness fields are formalized, local playlist and scoped-receipt counts now feed the schema, guest-pass/demo preference is represented in the shared contract, and provider-backed native balance now flows through `ContextService`.
- `P0-301` is now complete for the current read-only provider slice: endpoint resolution is centralized, NFT fetching is injected, gas pricing is protocol-backed, the shell service hub owns the shared provider factory, and native balance is consumed by the shell-facing context layer.
- `P0-701A` is now in progress as a structural scaffolding slice: root-owned mode state, a shell service hub, and shared receipt-store factories are in place.
- `P0-101C` remains blocked on `P0-302`, `P0-401`, `P0-402`, and `P0-403`.

## Remediation Closeout

The remediation checklist has been retired. Its durable outcomes now live in the ticket docs and this implementation-order plan.

Closeout summary:

- `P0-101A`: complete for the current root-shell contract
- `P0-201`: verified complete; keep `AccountStore` as the account CRUD seam
- `P0-501`: complete for the current receipt foundation baseline
- `P0-101E`: complete; keep in maintenance mode
- `P0-101B`: complete after chrome re-validation
- `P0-101D`: complete; keep in maintenance mode
- `P0-202`: complete with lowercase canonical normalization contract
- `P0-601`: complete for Phase 0 Observe-mode ownership
- `P0-204`: complete for the current per-account chain-scope baseline
- `P0-502`: complete for the current shell/context/action receipt slice; later verification and cleanup still belong to `P0-502B`
- `P0-402`: complete for the current shell-facing context-service slice; broader shell rollout and stricter boundary cleanup continue under the same ticket family
- `P0-401`: in progress as a stronger schema-first baseline; the remaining gaps are broader adoption and a few still-placeholder-safe fields, not missing balance/provider wiring
- `P0-301`: complete for the current injected read-only provider baseline; later token-surface consumers and stricter ownership cleanup remain deferred
- `P0-701A`: in progress as a shell/service scaffolding baseline; strict boundary enforcement remains deferred to `P0-701B`
- `P0-101C`: still blocked pending the real context/freshness stack

## Planning Rules

- `P0-101D` is a parallel foundation, not a universal hard blocker
- `P0-101B` comes before `P0-601`
- `P0-101B` should first ship with fixed Observe presentation
- `P0-502` is incremental by feature slice
- `P0-502B` is the later verification and cleanup pass
- `P0-701` is split into:
  - `P0-701A` early structural scaffolding
  - `P0-701B` later enforcement completion
- `P0-103B` can begin as pure parsing/classification before local enrichment
- `P0-451` can start with deterministic demo or local data
- `P0-461` can start with placeholder or local holdings data
- `P0-102A` can use placeholder-backed module data to break dependency cycles

## Recommended Order

### Phase 1: UI baseline and shell chrome

Completed

1. `P0-101E` Design system primitives
2. `P0-101B` Global Chrome UI with fixed Observe presentation
3. `P0-101D` Global error + empty-state patterns

Why:

- this gives the app a stable visual and shell baseline
- downstream tickets stop inventing one-off UI structure

### Phase 2: Immediate shell-adjacent follow-up

Completed

4. `P0-202` Address validation + normalization
5. `P0-601` Mode system Observe v0

Why:

- validation should settle before more account entry and search UX expands
- mode state should formalize after the chrome already exists

### Phase 3: Context and provider spine setup

Partially complete

Current phase status:

- `P0-204` is complete.
- `P0-301` is complete for the current read-only provider slice.
- `P0-401` and `P0-701A` have shipped meaningful baseline slices, but the phase is not complete yet.
- Full Phase 3 completion still depends on the remaining completion boundaries recorded in those ticket docs.

6. `P0-204` Chain scope settings per account (Completed)
7. `P0-401` Context schema v0 (Stronger schema-first slice in progress)
8. `P0-301` Provider abstraction (Completed for current read-only provider slice)
9. `P0-701A` Layered boundaries structural scaffolding (Baseline slice in progress)

Why:

- `P0-204` is now done, so the next real start point is `P0-401`
- `P0-401` now covers the shell-facing typed schema cleanly enough that the remaining work is mostly provider-backed enrichment and broader adoption, not missing contract shape
- `P0-301` now provides a real reusable provider seam, while `P0-701A` still owns structural follow-on cleanup
- this is the minimum structure needed before context orchestration becomes real

### Phase 4: Fetch, cache, and context assembly

10. `P0-502` initial receipt slices for the active work (Completed for current shell/context/explorer/copy slice)
11. `P0-302` Caching + freshness primitives (Completed for current context-sheet freshness contract)
12. `P0-402` Context service + dependency boundaries (Completed for strengthened shell-facing context slice)
13. `P0-303` Error handling + degraded mode (Completed for current shell-wide NFT provider-failure rollout)
14. `P0-203` ENS resolution + reverse lookup (Completed for planned first-pass ENS forward resolution and best-effort reverse display slice)

Why:
- this produces the real scoped read-only spine used by chrome, Home, and later search


### Phase 5: Receipts UI and early product surfaces

15. `P0-503` Receipts UI (Completed for scoped receipts timeline/detail slice)
21. `P0-103B` Query parser + type detection (Completed for deterministic local parser + inline detection feedback slice)
16. `P0-101C` Context Bar behavior + interactions
17. `P0-403` Context inspector UI

18. `P0-451` Music library index + storage
19. `P0-461` Token holdings list
20. `P0-102A` Home layout v0


Why:

- this phase unlocks visible user-facing surfaces without waiting for every downstream detail flow

### Phase 6: Home expansion and detail surfaces

22. `P0-102E` Home empty/first-run state
23. `P0-102B` Active account summary card
24. `P0-102C` OS-level shortcuts / modules section
25. `P0-102D` Recent activity preview
26. `P0-452` Music collection + item detail screens
27. `P0-462` Token detail screen

Why:

- these deepen the surfaces created in earlier phases instead of blocking them

### Phase 7: Search flow completion

28. `P0-103A` Search entry points
29. `P0-103C` Resolution pipeline
30. `P0-103D` Search results UI
31. `P0-103F` Search history
32. `P0-103E` No-results + safety behavior

Why:

- parser-first work starts earlier, but full search completion depends on the real read-only pipeline and safe action model

### Phase 8: Policy, enforcement, and trust hardening

33. `P0-602` Policy gate wrapper for actions
34. `P0-701B` Layered boundaries enforcement completion
35. `P0-702` Untrusted input labeling
36. `P0-703` No bypass paths smoke tests
37. `P0-502B` Receipt logging verification + cleanup

Why:

- this is the hardening pass after the main surfaces and action paths exist

### Phase 9: Release-readiness pass

38. `P0-801` Deterministic demo dataset + offline mode behavior
39. `P0-802` Performance + stability baseline
40. `P0-803` Privacy + security checklist for Phase 0

Why:

- these are most valuable once the feature surface is broad enough to measure and harden meaningfully

## Suggested Next Concrete Sprint

If the goal is to continue implementation immediately with the least churn, finish the still-open Phase 3 spine work first:

1. `P0-401`
2. `P0-701A`

That gives the project:

- a fully closed context snapshot contract instead of a schema-first baseline
- structural scaffolding that is ready for downstream chrome and surface work

`P0-301` no longer belongs in the next sprint list because the current read-only provider slice is already landed. The main unfinished shell-spine work is now `P0-401` and `P0-701A`.

## Suggested Following Sprint

After that, move into the blocked-but-nearest user-facing follow-ons that depend on the spine:

1. `P0-101C`
2. `P0-403`
3. `P0-102A`
4. `P0-451`
5. `P0-461`

That sequence turns the finished shell/context baseline into visible product surfaces instead of reopening already completed fetch, cache, and receipt-foundation tickets.

## Notes On Interpretation

- If a ticket can begin with placeholder-backed data without violating safety or architecture goals, start it rather than waiting for a perfect dependency chain.
- If a ticket defines enforcement or cleanup, delay it until the thing being enforced or cleaned up is real.
- If a ticket adds UI but depends on a missing source of truth, prefer a fixed safe presentation only when that sequencing decision has already been made explicitly, as with `P0-101B` before `P0-601`.
