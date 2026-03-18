# P0-461 Tickets And Session Handoff

## Summary

Implement the token holdings list for the active account and chain scope, with ETH minimum support and optional ERC-20 support.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Handle ETH-only lists, missing token metadata, and stale cached balances after fetch failure.

## Validation

Display native ETH balance, refresh with receipts and freshness updates, and show cached stale balances in offline mode.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
