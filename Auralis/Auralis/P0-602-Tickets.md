# P0-602 Tickets And Session Handoff

## Summary

Create the Phase 0 PolicyGate that allows only read-only actions and denies any execute or signing path with receipts.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Ensure denied actions have zero side effects, consistent behavior across screens, and safe allow-lists for copy/open/refresh.

## Validation

Audit action handlers, verify denied actions log policy receipts, and confirm allowed actions still proceed and log correctly.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
