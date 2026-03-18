# P0-103A Tickets And Session Handoff

## Summary

Expose Search from the global chrome on all major surfaces with a consistent presentation style and autofocus behavior.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Avoid modal stacking conflicts, keyboard focus bugs on first presentation, and layout issues on larger devices.

## Validation

Open search from all primary surfaces, dismiss and reopen repeatedly, and confirm navigation into and back out of detail screens works.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
