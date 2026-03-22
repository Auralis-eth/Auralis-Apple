# P0 Global Dependency And Sequence Report

This report reflects the corrected planning assumptions for the current Phase 0 ticket set.

Known completed foundations:

- `P0-101A` root navigation structure
- `P0-101B` global chrome UI first pass with fixed Observe presentation
- `P0-101D` global error and empty-state patterns
- `P0-101E` design system primitives
- `P0-202` address validation + normalization
- `P0-201` account model and persistence
- `P0-501` receipt schema, storage, sanitization, export, and reset foundation

The rest of the tickets in this batch are treated as not started unless noted below.

## Ready Now

- `P0-601` mode system Observe v0
- `P0-204` chain scope settings per account
- `P0-401` context schema v0 as a schema-first slice
- `P0-301` provider abstraction as an injected baseline slice
- `P0-701A` layered scaffolding as a shell/service baseline slice

## Newly Completed Foundation

- `P0-101D` global error and empty-state patterns

This now exists as a shared shell-status layer and should be reused by downstream tickets instead of replaced with one-off surfaces.

## Corrected Sequencing Rules

### `P0-101B` before `P0-601`

This is no longer treated as a deadlock.

Agreed order:

1. `P0-101B` with fixed Observe presentation
2. `P0-601` formal mode-state ownership and receipt inclusion

### `P0-502` is sliced, then verified later

`P0-502` should land incrementally inside each feature area.

Later broad verification and cleanup lives in:

- `P0-502B` Receipt logging verification + cleanup

### `P0-701` is split

- `P0-701A` early structural scaffolding
- `P0-701B` later enforcement completion

### Break cycles with placeholder-backed starts where allowed

Allowed early-start rules:

- `P0-103B` can start as pure parsing and classification before local index enrichment
- `P0-451` can start with deterministic demo or local index data
- `P0-461` can start with local or placeholder holdings data
- `P0-102A` can use placeholder-backed module data and previews before final module surfaces are complete

## Tickets Still Broadly Blocked

### Shell and chrome follow-ons

- `P0-101C` blocked by `P0-101B`, `P0-401`, `P0-402`, `P0-403`, `P0-302`

### Home expansion

- `P0-102B` blocked by `P0-102A`, `P0-203`, `P0-301`, `P0-302`
- `P0-102C` blocked by `P0-102A`, `P0-302`, `P0-451`, `P0-461`, `P0-502` slices
- `P0-102D` blocked by `P0-102A`, `P0-503`

### Search follow-ons

- `P0-103A` depends on `P0-101B`
- `P0-103C` blocked by `P0-103B`, `P0-302`, `P0-301`, and the needed `P0-502` slice
- `P0-103D` blocked by `P0-103C`, `P0-101A`
- `P0-103E` blocked by `P0-101D`, `P0-601`, `P0-602`, `P0-502`
- `P0-103F` blocked by `P0-103A`

### Identity, provider, and context spine

- `P0-203` blocked by `P0-301`, `P0-302`, and the needed `P0-502` slice
- `P0-204` closed for the current chain-scope baseline; later context-service integration continues in `P0-401` and `P0-402`
- `P0-301` is startable now and should align to `P0-701A` without waiting for later enforcement
- `P0-701A` is startable now with shell/service seams, but full boundary enforcement still waits for `P0-402` and `P0-701B`
- `P0-302` blocked by `P0-301`, `P0-401`, and the needed `P0-502` slice
- `P0-303` blocked by `P0-301`, `P0-302`, and the needed `P0-502` slice
- `P0-401` is startable now; full completion still depends on `P0-302`
- `P0-402` blocked by `P0-401`, `P0-301`, `P0-302`, `P0-701A`, and the needed `P0-502` slice
- `P0-403` blocked by `P0-101C`, `P0-402`, `P0-503`

### Library and detail surfaces

- `P0-452` blocked by `P0-451`, `P0-502`, `P0-702`
- `P0-462` blocked by `P0-461`, `P0-103D`, `P0-502`, `P0-702`

### Policy, boundaries, and hardening

- `P0-602` blocked by `P0-601`, `P0-502`, `P0-701A`
- `P0-701B` blocked by `P0-602`, `P0-701A`, `P0-402`
- `P0-702` blocked by `P0-452`, `P0-462`, `P0-101D`, `P0-602`
- `P0-703` blocked by `P0-602`, `P0-701B`, `P0-502B`
- `P0-801` blocked by `P0-451`, `P0-302`, `P0-303`
- `P0-802` blocked by `P0-503`, `P0-451`, `P0-461`
- `P0-803` stays later; it is not being pulled earlier

## Recommended Execution Sequence

### Tier 1

- `P0-101E`
- `P0-101B`
- `P0-101D`

### Tier 2

- `P0-202`
- `P0-601`

### Tier 3

- `P0-204`
- `P0-401`
- `P0-301`
- `P0-701A`

### Tier 4

- `P0-502` initial slices
- `P0-302`
- `P0-402`
- `P0-303`
- `P0-203`

### Tier 5

- `P0-503`
- `P0-101C`
- `P0-403`
- `P0-451`
- `P0-461`
- `P0-102A`
- `P0-103B`

### Tier 6

- `P0-102E`
- `P0-102B`
- `P0-102C`
- `P0-102D`
- `P0-452`
- `P0-462`

### Tier 7

- `P0-103A`
- `P0-103C`
- `P0-103D`
- `P0-103F`
- `P0-103E`

### Tier 8

- `P0-602`
- `P0-701B`
- `P0-702`
- `P0-703`
- `P0-502B`

### Tier 9

- `P0-801`
- `P0-802`
- `P0-803`

## Rule For Future Planning

If a ticket can start with placeholder-backed or parser-only work that breaks a dependency cycle cleanly, prefer that over declaring the whole feature blocked.
