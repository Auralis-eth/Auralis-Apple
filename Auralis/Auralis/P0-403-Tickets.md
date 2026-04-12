# P0-403 Tickets And Session Handoff

## Summary

Add the Why-am-I-seeing-this inspector with scope, provenance, freshness, and links to related receipts.

## Ticket Status

Completed for the current inspector slice.

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

## Latest Completion Note

- added a Why-am-I-seeing-this explanation section to the context inspector instead of leaving it as a raw schema dump
- linked the inspector to the latest scoped `context.built` receipt when available
- wired that receipt link into the existing receipt detail route so the inspector can hand off to the receipts surface directly
- kept the empty state honest when no related receipt exists for the active scope

## Remaining Note

- this ticket is complete for the current minimum vertical slice, not the final inspector end state
- richer provenance storytelling or larger receipt groups should wait until there is a concrete product need, not be guessed now
