# P0-403 Tickets And Session Handoff

## Summary

Add the Why-am-I-seeing-this inspector with scope, provenance, freshness, and links to related receipts.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Inspector should still work with no receipts, large details need collapse behavior, and stale offline context must be labeled clearly.

## Validation

Open from major screens, verify freshness and provenance display against real cache state, and navigate into linked receipt detail.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
