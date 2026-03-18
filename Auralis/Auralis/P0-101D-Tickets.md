# P0-101D Tickets And Session Handoff

## Summary

Create shared shell-level empty and error patterns for first-run, provider failure, no receipts, and empty library states.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Avoid banner stacking, preserve partial cached content on refresh failure, and clearly label demo content on first-run paths.

## Validation

Launch with no accounts, disable network while cached data exists, open receipts with none, and verify the library empty state offers only safe actions.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
