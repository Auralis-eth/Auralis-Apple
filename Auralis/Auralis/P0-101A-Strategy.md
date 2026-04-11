# P0-101A Strategy: Root navigation structure

## Status

Re-validated complete for the current root-shell contract

## Ticket

Establish the root shell navigation structure so primary destinations, owned detail stacks, receipts, search, and deep-link handoff all route through one coherent app-level contract.

## Dependencies

None for the shell baseline.

## Strategy

- Keep root ownership in the shell instead of scattering top-level routing across feature views.
- Make root tabs and owned detail stacks explicit.
- Ensure receipts and deep-link entry points are first-class shell destinations, not ad hoc overlays.

## Key Risk

Avoid building feature surfaces on top of unstable ownership rules, or letting deep links bypass the shell and land in inconsistent tab/detail state.

## Definition Of Done

- Primary shell destinations are explicit.
- Owned detail paths route through the shell router.
- Receipts and search exist as real root destinations.
- Receipt deep links hand off through the live shell without bypassing navigation ownership.

## Completion Note

Implemented as the current Phase 0 root-shell baseline:

- `AppRouter` owns top-level tab selection plus per-surface detail stacks.
- Receipts are mounted as a real root destination with owned receipt detail routing.
- Search is mounted as a real root destination instead of a placeholder shortcut.
- Deep-link parsing and pending-resolution logic hand destinations back to the owning shell routes.
- Home-launched NFT detail routing respects owning feature tabs instead of inventing duplicate detail shells.

## Validation Target

Verify root tab selection, receipt-route ownership, search-route ownership, home-to-detail handoff, and deep-link routing all resolve through the shell router contract.
