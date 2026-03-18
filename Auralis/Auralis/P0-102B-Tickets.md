# P0-102B Tickets And Session Handoff

## Summary

Create the Home summary card for identity, chain scope, balance, and freshness with copy and inspector/account-detail actions.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

ENS fallback, unavailable balance, and stale cached balances must read clearly without implying broken state.

## Validation

Copy address logs a receipt, balance refresh updates freshness, ENS fallback works, and forced stale cache timestamps update the label.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
