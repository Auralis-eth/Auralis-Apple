# P0 Global Dependency And Sequence Report

This report reflects the current ticket status recorded in the repo and supersedes the older assumption that most of the Phase 0 batch was still untouched.

Where ticket documents disagree, this report prefers the newest completion-facing artifact for that ticket:

- dependency report or tickets handoff over an older dependency note
- current strategy status over an older planning-only statement

## Confirmed Complete Or Implemented

These tickets are already closed for their planned Phase 0 slice:

- `P0-101A` root navigation structure
- `P0-101B` global chrome UI first pass
- `P0-101D` global error and empty-state patterns
- `P0-101E` design system primitives
- `P0-201` account model and persistence
- `P0-202` address validation + normalization
- `P0-203` ENS resolution first pass
- `P0-204` chain scope settings per account
- `P0-301` provider abstraction first pass
- `P0-302` caching + freshness primitives for the current Phase 0 contract
- `P0-303` provider-failure and degraded-mode slice
- `P0-402` active shell context-service slice
- `P0-501` receipt schema, storage, sanitization, export, and reset foundation
- `P0-502` active account and chain-scope receipt integration slice
- `P0-503` receipts UI timeline + filters
- `P0-601` Observe-only mode ownership
- `P0-103B` query parser + type detection
- `P0-102E` Home empty/first-run state
- `P0-102B` active account summary card
- `P0-102C` OS-level shortcuts / modules section
- `P0-102D` recent activity preview
- `P0-103A` search entry points
- `P0-103C` resolution pipeline
- `P0-103D` search results UI
- `P0-103E` no-results + safety behavior
- `P0-103F` search history
- `P0-602` policy gate wrapper for actions
- `P0-701A` layered module-boundary scaffolding
- `P0-701B` layered boundaries enforcement completion
- `P0-702` untrusted input labeling
- `P0-703` no bypass paths smoke tests
- `P0-451` music library index derived from the existing SwiftData-backed local `NFT` store
- `P0-452` music collection + item detail screens
- `P0-461` provider-backed SwiftData-backed token holdings slice
- `P0-462` token detail screen

Notes:

- Treat `P0-203` as complete for its planned first pass. Its strategy file still says `Ready`, but its dependency report and completion summary say the work is delivered.
- `P0-302`, `P0-303`, `P0-402`, `P0-502`, and `P0-503` were previously shown as blocked or later-tier work in older planning material. That is no longer accurate.

## In Progress

There are no remaining in-progress tickets in the former shell-spine batch.

Current read on `P0-401`:

- the shell-facing `ContextSnapshot` contract is real and in use
- local playlist and scoped-receipt counts now feed the schema where local data already exists
- guest-pass/demo preference is represented in the shared context contract
- provider-backed native balance now flows through `ContextService`
- shell-owned pinned Home links now feed a real pinned-item preference count instead of a placeholder-safe field

Current read on `P0-301`:

- the shared read-only provider factory is real and mounted in the shell service hub
- NFT inventory, gas pricing, and native balance reads all flow through the provider abstraction story
- native balance is no longer stranded at the protocol layer; the shell-facing context path consumes it

Current read on `P0-101C`:

- the product keeps a dedicated Context entry in chrome instead of a separate freshness pill
- the inspector freshness section now exposes stale/unknown/no-success refresh behavior through the existing shell refresh path
- the chrome now surfaces freshness and scope state visibly while keeping the inspector as the dedicated interaction surface

Current read on `P0-403`:

- the context inspector now includes a Why-am-I-seeing-this section
- it links to the latest scoped `context.built` receipt and can hand off into receipt detail
- this ticket is complete for the current vertical slice; remaining ideas are optional inspector expansion, not missing baseline functionality

Current read on `P0-102A`:

- Home now has a real dashboard shell with identity, modules, recent activity, quick links, and temporary profile-studio sections
- the scenic background and glass-card visual language were intentionally preserved
- Home now includes an explicit active-scope summary and a dedicated quick-links section with pinned shortcuts
- later Home tickets can now deepen sections without forcing another top-level Home rewrite

## Still Blocked

These tickets remain blocked in their own current docs:

- `P0-801`
- `P0-802`
- `P0-803`

## Corrected Dependency Read

### `P0-101B` before `P0-601`

This sequence is finished, not merely agreed:

1. `P0-101B` landed for the current chrome contract.
2. `P0-601` formalized Observe-only mode ownership and receipt inclusion.

### `P0-502` remains incremental

The original slicing rule still stands, but the report must now acknowledge completed slices:

- `P0-502` active account and chain-scope integration is complete
- `P0-502B` is now complete for the current verification-and-cleanup slice, with payload hygiene tightened for mounted link/copy flows and no schema reset

### `P0-701` remains split

- `P0-701A` is complete for the structural scaffolding slice
- `P0-701B` is complete for the first shell-facing enforcement slice, with deeper leaf-view cleanup still intentionally deferred

### Context and provider work moved forward materially

Older planning assumed the following work was still pending before many downstream tickets could move:

- `P0-302`
- `P0-303`
- `P0-402`

That assumption is stale. Those slices are now delivered for their current Phase 0 scope, which changes the real downstream posture.

## Practical Next Sequence

Given the current repo state, the most defensible next sequencing is:

### Shell Spine Read

- `P0-301`, `P0-401`, `P0-701A`, and `P0-101C` are complete for their current slices

### Phase 8 Closure Read

- the Home expansion and detail-surface phase is complete for its current slice
- no remaining Phase 8 tickets are still merely startable, partially blocked, or blocked in the current docs

Status nuance:

- `P0-452` is complete for the current Music detail slice
- `P0-462` is complete for the current token-detail slice

### Phase 9 Closure Read

- the search flow completion phase is complete for the current slice
- search now has a single rooted entry contract, typed local-first routing, no-results and safety states, and committed per-account history

### Phase 10 Closure Read

- the policy, enforcement, trust-labeling, smoke-test, and receipt-cleanup hardening phase is complete for the current slice
- the remaining late work is now Phase 11 release-readiness, not unresolved shell or policy hardening

## Planning Rule Going Forward

If a ticket has a newer completion report, strategy status, or handoff summary that contradicts an older dependency note, update the global report to the newer artifact instead of preserving the older planning assumption.
