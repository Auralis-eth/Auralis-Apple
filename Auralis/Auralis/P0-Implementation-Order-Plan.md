# P0 Implementation Order Plan

This file is the practical implementation sequence for the current Phase 0 ticket set.

It is not a restatement of every raw JIRA dependency. It is the working order intended to get the project moving while respecting the dependency decisions already made in planning.

## Known Completed Foundations

- `P0-101A` Root navigation structure
- `P0-101B` Global Chrome UI first pass with fixed Observe presentation
- `P0-101D` Global error + empty-state patterns
- `P0-101E` Design system primitives
- `P0-201` Account model + persistence
- `P0-501` Receipt schema, append-only store, sanitization, export, and reset foundation

## Current Status Note

- `P0-101B` is implemented and builds, but the global chrome layout is still being tuned so it reads as part of the shell instead of covering feature content.
- Do not reorder the sprint sequence because of that tuning work; treat it as follow-up refinement inside the completed first-pass chrome ticket.
- `P0-101D` is implemented as the shared shell-status layer for first-run, provider failure, no-receipts, and empty-library states.

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

1. `P0-101E` Design system primitives
2. `P0-101B` Global Chrome UI with fixed Observe presentation
3. `P0-101D` Global error + empty-state patterns

Why:

- this gives the app a stable visual and shell baseline
- downstream tickets stop inventing one-off UI structure

### Phase 2: Immediate shell-adjacent follow-up

4. `P0-202` Address validation + normalization
5. `P0-601` Mode system Observe v0

Why:

- validation should settle before more account entry and search UX expands
- mode state should formalize after the chrome already exists

### Phase 3: Context and provider spine setup

6. `P0-204` Chain scope settings per account
7. `P0-401` Context schema v0
8. `P0-301` Provider abstraction
9. `P0-701A` Layered boundaries structural scaffolding

Why:

- this is the minimum structure needed before context orchestration becomes real

### Phase 4: Fetch, cache, and context assembly

10. `P0-502` initial receipt slices for the active work
11. `P0-302` Caching + freshness primitives
12. `P0-402` Context service + dependency boundaries
13. `P0-303` Error handling + degraded mode
14. `P0-203` ENS resolution + reverse lookup

Why:

- this produces the real scoped read-only spine used by chrome, Home, and later search

### Phase 5: Receipts UI and early product surfaces

15. `P0-503` Receipts UI
16. `P0-101C` Context Bar behavior + interactions
17. `P0-403` Context inspector UI
18. `P0-451` Music library index + storage
19. `P0-461` Token holdings list
20. `P0-102A` Home layout v0
21. `P0-103B` Query parser + type detection

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

## Suggested First Concrete Sprint

If the goal is to start implementation immediately with the least churn, begin here:

1. `P0-101E`
2. `P0-101B`
3. `P0-101D`
4. `P0-202`
5. `P0-601`

That gives the project:

- reusable UI primitives
- global chrome
- shared empty/error patterns
- locked input validation behavior
- formal Observe mode ownership

## Suggested Next Concrete Sprint

With `P0-101D` now complete, the next recommended sprint is:

1. `P0-202`
2. `P0-601`
3. `P0-204`

Why:

- `P0-202` can now converge onto the shared shell messaging instead of keeping auth-specific one-off alerts
- `P0-601` is the next shell-adjacent cross-cutting state formalization
- `P0-204` is the clean entry into the context/provider spine once shell-adjacent follow-up is settled

## Suggested Second Sprint

After that, move directly into the context spine:

1. `P0-204`
2. `P0-401`
3. `P0-301`
4. `P0-701A`
5. `P0-302`
6. `P0-402`

## Notes On Interpretation

- If a ticket can begin with placeholder-backed data without violating safety or architecture goals, start it rather than waiting for a perfect dependency chain.
- If a ticket defines enforcement or cleanup, delay it until the thing being enforced or cleaned up is real.
- If a ticket adds UI but depends on a missing source of truth, prefer a fixed safe presentation only when that sequencing decision has already been made explicitly, as with `P0-101B` before `P0-601`.
