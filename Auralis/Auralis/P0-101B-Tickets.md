# P0-101B Tickets And Session Handoff

## Summary

Implement the always-visible OS chrome header across primary surfaces, including account switcher, mode badge, freshness indicator, search entry, and context inspector entry.

## Execution Order

1. Confirm the mount points in the existing shell and routed surfaces.
2. Implement the chrome shell with fixed Observe presentation first.
3. Wire account switching, freshness display, search entry, and context-inspector entry.
4. Cover truncation and stale or offline display edge cases.

## Critical Edge Case

Handle long ENS or nickname truncation, address fallback, compact multi-chain display, and stale or offline freshness states without collapsing the header.

## Validation

Verify chrome appears on Home, Music, Tokens, Details, and Receipts; account switching updates scope; mode badge stays Observe; search opens from every surface; freshness updates after refresh.

## Handoff Rule

If `P0-601` is not done yet, keep the badge visually fixed to Observe and avoid burying mode-state ownership inside the chrome layer.

## Implementation Result

- added [`Auralis/Auralis/Aura/GlobalChromeView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/GlobalChromeView.swift) as the shared first-pass chrome layer
- mounted the chrome once at the `MainTabView` level via a top `safeAreaInset`, so it stays visible across the primary tab surfaces and routed detail flows
- wired the account entry to the existing [`Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift)
- kept the mode badge visually fixed to `Observe`
- wired the search entry to the existing search tab and replaced the old search stub with a fixed placeholder surface in [`Auralis/Auralis/Aura/MainTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainTabView.swift)
- added a context-inspector sheet placeholder in [`Auralis/Auralis/Aura/GlobalChromeView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/GlobalChromeView.swift) so the seam exists without pulling `P0-403` forward
- added `lastSuccessfulRefreshAt` to [`Auralis/Auralis/Networking/NFTService.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTService.swift) so the chrome can show a real freshness signal instead of a fake badge

## Deferred By Design

- final mode-state ownership still belongs to `P0-601`
- real search resolution/results flow still belongs to the search ticket chain
- full context inspector behavior still belongs to `P0-403`
- receipts UI remains outside the scope of this first-pass chrome ticket

## Validation Result

- the project built successfully after the chrome integration
