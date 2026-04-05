# P0-102C Tickets And Session Handoff

## Summary

Deepen the Home modules section into a more intentional shortcut and launcher surface.

## Ticket Status

Completed for the current slice.

## Execution Checklist

### 1. Confirm the launcher contract

- [x] Re-read `P0-102C-Strategy.md` and `P0-102C-Dependency-Note.md`.
- [x] Confirm which modules belong in the first pass.
- [x] Confirm which existing routes should back each shortcut.

Launcher contract notes:

- The seam is the existing `modulesSection` in `HomeTabView`, not the separate `quickLinksSection` and not a new top-level Home area.
- The current first-pass module candidates already mounted in that slot are:
  - `Music`, backed by `router.showMusicLibrary()`
  - `NFT Tokens`, backed by `router.showNFTTokens()`
- Real shell routes also exist for `Search`, `News`, and `Receipts`, but those currently live in the adjacent quick-links area. They are valid launcher destinations in the product, yet they should not be silently absorbed into `P0-102C` unless the module hierarchy intentionally promotes them into the modules section.
- The first pass should therefore deepen the module launcher around real mounted product surfaces without reopening Home sparse-state behavior, the active-account summary card, or profile-studio controls.
- A safe boundary for step 2 is: refine module hierarchy and module tile behavior using already-real destinations, while leaving temporary profile controls and one-off quick links outside the module system unless they are deliberately promoted.

### 2. Implement the upgraded modules section

- [x] Refine the tile set and module hierarchy.
- [x] Route modules to real product surfaces.
- [x] Preserve the current Home visual language.

Implementation notes:

- The `modulesSection` in `HomeTabView` is now the real launcher layer instead of a loose pair of tiles plus a separate quick-links card.
- The hierarchy is now explicit:
  - primary module cards: `Music` and `NFT Tokens`
  - secondary shell shortcuts: `Search`, `News Feed`, and `Receipts`
- All launcher actions route only to already-mounted shell destinations:
  - `showMusicLibrary()`
  - `showNFTTokens()`
  - `showSearch()`
  - `selectedTab = .news`
  - `showReceipts()`
- The module ordering and sparse-music copy are now driven by `HomeTabLogic.modulesPresentation(...)` so later edge-case and ordering checks do not depend on view rendering.
- The existing Aura card language was preserved by keeping the glass-card treatment, section headers, and `AuraActionButton` interaction style.

### 3. Cover required edge cases

- [x] Module actions remain usable in sparse-data states.
- [x] Unavailable features fail honestly instead of pretending they are live.
- [x] Shortcut ordering stays intentional as modules expand.

Edge-case coverage notes:

- `HomeTabLogic.modulesPresentation(...)` now carries the launcher contract so sparse-data behavior and shortcut ordering can be validated without depending on UI rendering.
- Sparse-data coverage now proves that the same real shell shortcuts remain reachable even when local music is empty, so the launcher does not collapse just because the scope is still thin.
- Honest-failure coverage is expressed by exclusion: the first-pass launcher exposes only already-real destinations (`Music`, `NFT Tokens`, `Search`, `News Feed`, `Receipts`) and does not advertise unfinished or speculative modules.
- Ordering coverage now locks the primary-vs-secondary launcher hierarchy so later module additions have to make an explicit decision instead of silently shuffling the Home launcher taxonomy.

### 4. Validate the vertical slice

- [x] Verify each first-pass module lands on the intended route.
- [x] Verify the section still reads cleanly on smaller screens.
- [x] Record future module additions outside this ticket.

Validation notes:

- `Auralis` builds successfully with the upgraded launcher section in place.
- The full `HomeTabLogicTests` suite passed for the current Home slice, including sparse-state, summary-card, and launcher coverage:
  - sparse Home state routing and suppression behavior
  - active-account summary-card contract
  - launcher primary/secondary ordering
  - sparse-data launcher reachability
  - exclusion of pretend destinations
- Within the no-UI-tests constraint, route validation is covered through the explicit `HomeLauncherAction` contract and the launcher presentation tests that lock the exposed first-pass destinations to real shell routes only.
- Smaller-screen readability remains protected by the existing `shouldStackTiles` layout branch, which is still used by both primary module cards and shell shortcut buttons after the launcher refactor.
- Follow-ons explicitly left outside `P0-102C`:
  - adding new launcher destinations that do not yet have real mounted surfaces
  - deeper per-module destination behavior
  - broader Home visual redesign beyond the launcher hierarchy cleanup

## Critical Edge Case

The modules section must stay coherent even when some destinations are sparse, empty, or not yet deeply built out.

## Validation

Launch real surfaces from the Home modules section and keep the tile system useful without overloading it.

## Handoff Rule

If the section starts absorbing unrelated feature work, stop and split the follow-on module behavior into its own ticket.
