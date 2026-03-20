# P0-101B Dependency Report

This document records the dependency posture, delivered scope, deferred scope, and validation state for `P0-101B`.

`P0-101B` is complete for its planned first pass.

## Ticket

JIRA: `P0-101B`

Goal:

- implement the always-visible global chrome header across the primary shell surfaces
- keep the mode badge visually fixed to `Observe` for the first pass
- expose explicit seams for account switching, freshness, search, and context inspection

## Dependency Status

Satisfied dependencies:

- `P0-101A` Root navigation structure
- `P0-201` Account model + persistence
- `P0-101E` Design system primitives

Not required before starting and intentionally deferred:

- `P0-601` Mode system Observe v0

Planning rule preserved by this implementation:

- build chrome first with fixed Observe presentation
- do not invent final mode-state ownership inside the chrome layer

## Delivered Chrome Layer

Primary delivered file:

- [`Auralis/Auralis/Aura/GlobalChromeView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/GlobalChromeView.swift)

Supporting integration files:

- [`Auralis/Auralis/Aura/MainTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainTabView.swift)
- [`Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift)
- [`Auralis/Auralis/Networking/NFTService.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTService.swift)

Delivered chrome behaviors:

- the chrome is mounted once at the `MainTabView` layer via a top `safeAreaInset`
- the account entry opens the existing account switcher
- the mode badge is visibly fixed to `Observe`
- the freshness indicator is backed by a real `lastSuccessfulRefreshAt` value on `NFTService`
- the search entry routes into the existing search tab
- the context inspector exists as a safe placeholder sheet seam
- the mode badge now reads from the global `modeState` provided by `P0-601` (replacing the earlier fixed label)

## Production Mounting

Chrome mount point:

- [`Auralis/Auralis/Aura/MainTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainTabView.swift)

Why this mount point:

- it keeps the chrome always visible across the primary tab surfaces
- routed detail flows inherit the same chrome without per-screen duplication
- it avoids copy-pasting header logic into Home, News, Music, Tokens, and detail screens

## Search And Inspector Seams

Search first pass:

- the chrome search entry now routes into the search tab
- the old search stub was replaced with a deliberate placeholder surface in [`Auralis/Auralis/Aura/MainTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainTabView.swift)

Context inspector first pass:

- a placeholder context-inspector sheet exists in [`Auralis/Auralis/Aura/GlobalChromeView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/GlobalChromeView.swift)
- this preserves the seam without pulling `P0-403` implementation into `P0-101B`

## Deferred By Design

Still owned by later tickets:

- final mode-state ownership is provided by `P0-601`; the chrome now reads from this source of truth
- full context inspector behavior belongs to `P0-403`
- real search resolution/results flow belongs to the search ticket chain
- receipts UI remains outside this first-pass chrome ticket

## Edge Cases Covered

Chrome-specific edge cases addressed in the first pass:

- long account names fall back safely to address-based display
- compact chain display stays within the shared account summary row
- freshness has explicit fixed states instead of decorative placeholder text
- the Observe badge remains visually stable instead of acting like a hidden future mode switcher

## Validation

Completed validation:

- the project built successfully after the chrome integration

Residual limitation:

- this is intentionally a fixed Observe first pass; it validates chrome structure and seams, not final mode ownership behavior

## Completion Summary

`P0-101B` is complete for the planned first pass because:

- the global chrome exists and is visible from the shared shell
- account switching, search entry, freshness display, and context-inspector entry are all wired with explicit seams
- the mode badge is correctly fixed to `Observe`
- the ticket avoids smuggling `P0-601` or `P0-403` into the chrome layer

