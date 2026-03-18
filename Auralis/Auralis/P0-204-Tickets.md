# P0-204 Tickets And Session Handoff

## Summary

Add per-account chain scope settings that drive Context Builder and downstream library surfaces.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Prevent empty chain scope, handle out-of-scope detail screens gracefully, and design a list that can grow later.

## Validation

Persist chain scope per account, trigger context rebuild and receipts on scope change, and verify library surfaces respect the selected scope.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
