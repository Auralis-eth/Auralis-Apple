# P0-101B Tickets And Session Handoff

## Summary

Implement the always-visible global chrome header across the primary shell surfaces, including account switcher, mode badge, search entry, and context inspector entry.

## Ticket Status

Completed for the current Phase 0 chrome contract.

## Execution Checklist

### 1. Confirm the shell mount

- [x] Keep the chrome mounted once at the shell level.
- [x] Keep account, search, and context entry seams explicit.
- [x] Preserve the first-pass rule that the chrome does not invent final mode ownership itself.

### 2. Implement the first chrome slice

- [x] Mount the chrome across the primary shell surfaces.
- [x] Keep the mode badge visibly fixed to Observe for the first pass, later backed by `ModeState`.
- [x] Route account switching, search entry, and context inspection through the owning shell paths.

### 3. Cover required edge cases

- [x] Long account names degrade cleanly to address display.
- [x] Compact scope and freshness state remain readable.
- [x] The header stays stable across chain changes and routed detail screens.

### 4. Validate the vertical slice

- [x] Verify chrome is visible on the intended primary surfaces.
- [x] Verify account switching updates visible scope.
- [x] Verify search and context entry remain reachable from chrome.

## Implementation Notes

- The global chrome is implemented in `Auralis/Auralis/Aura/GlobalChromeView.swift`.
- `MainTabView` mounts that chrome once so routed detail stacks inherit the same shell header.
- The account affordance opens the existing account switcher instead of introducing another identity surface.
- Search entry routes into the mounted search tab.
- The context inspector seam remains explicit without pulling full inspector behavior into this ticket.

## Validation Notes

- The dependency report records a successful project build after the chrome integration.
- Contract coverage exists in `AuralisTests/GlobalChromeContractTests.swift`.
- Shell integration is backed by the current `MainTabView` mount and the completed `P0-101C` / `P0-601` follow-on slices.

## Critical Edge Case

The chrome must stay readable and stable across long account labels, compact widths, and stale or offline freshness states.

## Handoff Rule

If later work wants richer freshness storytelling or deeper inspector behavior, extend `P0-101C` or `P0-403` instead of reopening the core chrome mount.
