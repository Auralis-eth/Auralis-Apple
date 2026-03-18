# P0-601 Tickets And Session Handoff

## Summary

Implement the global Observe-only mode state, display it in chrome, persist it in app state, and include it in receipts.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Avoid incorrect mode state after restore and avoid confusing users with disabled future mode-switch UI.

## Validation

Mode badge always shows Observe, receipts include mode=Observe, and any execute placeholder is denied and logged.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
