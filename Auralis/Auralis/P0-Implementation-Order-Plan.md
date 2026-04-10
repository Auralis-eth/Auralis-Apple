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
- `P0-401` is now complete for the current Phase 0 context-contract slice: `ContextSnapshot` exists, the shell inspector reads it, provenance-bearing scope/freshness fields are formalized, local playlist and scoped-receipt counts now feed the schema, guest-pass/demo preference is represented in the shared contract, shell-owned pinned Home links now provide a real pinned-item preference count, and provider-backed native balance now flows through `ContextService`.
- `P0-301` is now complete for the current read-only provider slice: endpoint resolution is centralized, NFT fetching is injected, gas pricing is protocol-backed, the shell service hub owns the shared provider factory, and native balance is consumed by the shell-facing context layer.
- `P0-701A` is now complete as a structural scaffolding slice: root-owned mode state, a shell service hub, shared receipt-store factories, and a shell-owned pinned-link preference seam are in place.
- `P0-101C` is now complete under the context-sheet interpretation: the chrome keeps a dedicated inspector entry, visibly surfaces scope and freshness state, and the inspector freshness section handles stale labeling plus explicit refresh.
- `P0-403` is now complete for the current receipt-aware inspector slice: the sheet has a Why-am-I-seeing-this section and can link to the latest scoped `context.built` receipt.
- `P0-102A` is now complete as a conservative Home dashboard pass: the scenic glass aesthetic remains intact while Home is reorganized into identity, active scope summary, modules, quick links, recent activity, and temporary profile-studio sections.
- `P0-451` is now complete for the current Music foundation slice: a SwiftData-backed music library index exists, it rebuilds from scoped local `NFT` records, emits dedicated library-index receipts, the mounted Music tab consumes the index, and Home now shows the local music count while Search remains attached through the local `NFT` store.
- `P0-461` is now complete for the native-balance-first holdings slice: the ERC-20 tab mounts a real SwiftData-backed holdings list, native balance persists per account and chain scope, and the surface keeps cached native state visible when later refreshes fail.

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
- `P0-401`: complete for the current context-contract baseline; later schema growth remains additive follow-on work
- `P0-301`: complete for the current injected read-only provider baseline; later token-surface consumers and stricter ownership cleanup remain deferred
- `P0-701A`: complete as a shell/service scaffolding baseline; strict boundary enforcement remains deferred to `P0-701B`
- `P0-101C`: complete for the current context-sheet freshness interaction slice
- `P0-403`: complete for the current receipt-aware inspector slice
- `P0-102A`: complete for the current Home dashboard shell slice
- `P0-451`: complete for the current SwiftData-backed music library index slice
- `P0-461`: complete for the current native-balance-first holdings slice; provider-backed account token holdings retrieval remains deferred follow-on work

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
- `P0-451` can start by deriving its first library index from the existing SwiftData-backed local `NFT` store
- `P0-461` can start with placeholder or local holdings data
- provider-backed account token holdings retrieval remains a separate follow-on after `P0-461`; do not retroactively expand the ticket to claim full ERC-20 network enrichment
- `P0-102A` can use placeholder-backed module data to break dependency cycles

## Upcoming Ticket Status Snapshot

- `P0-461`: complete for the native-balance-first holdings slice
- `P0-102E`: complete for the Home empty/first-run state slice
- `P0-102B`: complete for the active account summary-card slice
- `P0-102C`: complete for the Home modules/shortcuts slice
- `P0-102D`: complete for the recent-activity preview slice
- `P0-452`: complete for the current Music collection and item-detail slice
- `P0-462`: complete for the current token-detail slice; provider-backed enrichment, pricing, and history remain later follow-ons
- `P0-103A`: complete for the search entry-point slice
- `P0-103C`: complete for the typed local-first search-resolution slice
- `P0-103D`: complete for the route-backed search results UI slice
- `P0-103F`: complete for the committed per-account search-history slice
- `P0-103E`: complete for the no-results and safety-state slice
- `P0-602`: complete for the shared policy-gate wrapper slice
- `P0-701B`: complete for the current first layered-enforcement slice; deeper leaf-view cleanup and later smoke testing remain follow-on work
- `P0-702`: complete for the current first trust-label slice; broader rollout across every provider-backed field remains follow-on work
- `P0-703`: complete for the current first no-bypass smoke-test slice; broader smoke expansion remains follow-on work
- `P0-502B`: complete for the current receipt verification-and-cleanup slice
- `P0-801`: startable for deterministic demo/offline behavior definition
- `P0-802`: partially blocked until the representative mounted flows are settled enough to benchmark honestly
- `P0-803`: startable for the Phase 0 privacy/security checklist pass

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

Completed

Current phase status:

- `P0-204` is complete.
- `P0-301` is complete for the current read-only provider slice.
- `P0-401` is complete for the current context-contract slice.
- `P0-701A` is complete for the current structural scaffolding slice.

6. `P0-204` Chain scope settings per account (Completed)
7. `P0-401` Context schema v0 (Completed for the current slice)
8. `P0-301` Provider abstraction (Completed for current read-only provider slice)
9. `P0-701A` Layered boundaries structural scaffolding (Completed for the current slice)

Why:

- `P0-204` is now done, and the rest of the phase is now closed for the current shell spine
- `P0-401` now covers the shell-facing typed schema cleanly enough for the current slice
- `P0-301` now provides a real reusable provider seam, and `P0-701A` has landed the structural scaffolding needed for shell-facing seams
- this is the minimum structure needed before context orchestration becomes real

### Phase 4: Fetch, cache, and context assembly

10. `P0-502` initial receipt slices for the active work (Completed for current shell/context/explorer/copy slice)
11. `P0-302` Caching + freshness primitives (Completed for current context-sheet freshness contract)
12. `P0-402` Context service + dependency boundaries (Completed for strengthened shell-facing context slice)
13. `P0-303` Error handling + degraded mode (Completed for current shell-wide NFT provider-failure rollout)
14. `P0-203` ENS resolution + reverse lookup (Completed for planned first-pass ENS forward resolution and best-effort reverse display slice)

Why:
- this produces the real scoped read-only spine used by chrome, Home, and later search


### Phase 5: Receipts UI, context, and Home shell surfaces

15. `P0-503` Receipts UI (Completed for scoped receipts timeline/detail slice)
21. `P0-103B` Query parser + type detection (Completed for deterministic local parser + inline detection feedback slice)
16. `P0-101C` Context Bar behavior + interactions (Completed for context-sheet freshness interaction slice)
17. `P0-403` Context inspector UI (Completed for current receipt-aware inspector slice)
20. `P0-102A` Home layout v0 (Completed for dashboard shell slice)


Why:

- this phase closes the shell/context loop and establishes the first real Home shell without waiting for every downstream detail flow

### Phase 6: Music library foundation

Completed

18. `P0-451` Music library index + storage (Completed)

Why:

- this is large enough to deserve its own phase boundary before collection/detail follow-ons
- the index and storage work becomes a dependency source for Home, Search, and later Music surfaces

### Phase 7: Token holdings foundation

Completed for the current slice

19. `P0-461` Token holdings list (Completed for native-balance-first SwiftData-backed holdings)

Why:

- token holdings have their own provider, cache, freshness, and surface-shape concerns
- separating them from Music avoids hiding a substantial token track inside a mixed phase
- the next real token follow-on is no longer “create the holdings surface”; it is “add a provider-backed account token holdings API call and persist the returned rows”

### Phase 8: Home expansion and detail surfaces

22. `P0-102E` Home empty/first-run state (Completed)
23. `P0-102B` Active account summary card (Completed)
24. `P0-102C` OS-level shortcuts / modules section (Completed)
25. `P0-102D` Recent activity preview (Completed)
26. `P0-452` Music collection + item detail screens (Completed)
27. `P0-462` Token detail screen (Completed)

Why:

- these deepen the surfaces created in earlier phases instead of blocking them

### Phase 9: Search flow completion

28. `P0-103A` Search entry points (Completed)
29. `P0-103C` Resolution pipeline (Completed)
30. `P0-103D` Search results UI (Completed)
31. `P0-103F` Search history (Completed)
32. `P0-103E` No-results + safety behavior (Completed)

Why:

- parser-first work starts earlier, but full search completion depends on the real read-only pipeline and safe action model

### Phase 10: Policy, enforcement, and trust hardening

33. `P0-602` Policy gate wrapper for actions (Completed)
34. `P0-701B` Layered boundaries enforcement completion (Completed)
35. `P0-702` Untrusted input labeling (Completed)
36. `P0-703` No bypass paths smoke tests (Completed)
37. `P0-502B` Receipt logging verification + cleanup (Completed)

Why:

- this is the hardening pass after the main surfaces and action paths exist

### Phase 11: Release-readiness pass

38. `P0-801` Deterministic demo dataset + offline mode behavior
39. `P0-802` Performance + stability baseline
40. `P0-803` Privacy + security checklist for Phase 0

Why:

- these are most valuable once the feature surface is broad enough to measure and harden meaningfully

## Suggested Next Concrete Sprint

The former Phase 3 spine blockers are now closed. The next remaining implementation work sits in Phase 11 release-readiness rather than unresolved shell-spine fundamentals.

## Suggested Following Sprint

After that, move into the next hardening and policy pass now that the search slice is complete:

1. `P0-602`
2. `P0-701B`
3. `P0-702`
4. `P0-703`

That sequence hardens the now-landed shell, Home, music, token, and search surfaces instead of reopening already completed feature slices.

## Notes On Interpretation

- If a ticket can begin with placeholder-backed data without violating safety or architecture goals, start it rather than waiting for a perfect dependency chain.
- If a ticket defines enforcement or cleanup, delay it until the thing being enforced or cleaned up is real.
- If a ticket adds UI but depends on a missing source of truth, prefer a fixed safe presentation only when that sequencing decision has already been made explicitly, as with `P0-101B` before `P0-601`.
