# P0-101A Tickets And Session Handoff

## Summary

Establish the root shell navigation structure so primary destinations, owned detail stacks, receipts, search, and deep-link handoff all route through one coherent app-level contract.

## Ticket Status

Completed for the current root-shell contract.

## Execution Checklist

### 1. Confirm root ownership

- [x] Keep root route ownership in the shell.
- [x] Make top-level tabs and per-tab detail stacks explicit.
- [x] Keep receipts and search as first-class root destinations.

### 2. Implement the shell router contract

- [x] Land a root-owned `AppRouter` for tab selection and owned detail paths.
- [x] Route Home-launched NFT detail through the owning feature tab instead of duplicating detail shells.
- [x] Mount Receipts and Search as real shell surfaces.

### 3. Cover required edge cases

- [x] Deep links do not bypass shell ownership.
- [x] Receipt routing stays inside the mounted receipts path.
- [x] Resetting navigation clears detail stacks without losing the selected top-level destination.

### 4. Validate the vertical slice

- [x] Verify root tab selection and owned detail navigation.
- [x] Verify receipt routes and search routes resolve through the shell.
- [x] Verify pending deep links replay through the live shell contract.

## Implementation Notes

- `AppRouter` now owns the active tab plus per-surface detail stacks for News, Music, Profile, Receipts, NFT Tokens, and ERC-20 Tokens.
- Receipts are mounted as a real root destination with owned receipt detail routing.
- Search is mounted as a real root destination instead of an ad hoc shortcut.
- Home-launched NFT detail respects feature ownership: music NFTs route to Music, non-music NFTs route to NFT Tokens.
- Deep-link parsing and pending-resolution logic hand off through the shell router instead of bypassing navigation ownership.

## Validation Notes

- Root-navigation coverage exists in `AuralisTests/AppRouterTests.swift`.
- Deep-link parsing coverage exists in `AuralisTests/AppDeepLinkParserTests.swift`.
- Pending replay and shell-handoff coverage exists in `AuralisTests/PendingDeepLinkResolverTests.swift`.
- The current root-shell baseline is also marked complete in `P0-Implementation-Order-Plan.md` and `P0-Global-Dependency-Sequence-Report.md`.

## Critical Edge Case

Deep links must not land the app in a tab/detail state the shell does not own.

## Handoff Rule

If a later route needs a new destination, add it to the shell router contract instead of creating feature-local navigation side channels.
