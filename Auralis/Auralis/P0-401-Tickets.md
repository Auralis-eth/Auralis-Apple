# P0-401 Tickets And Session Handoff

## Summary

Define the scoped ContextSnapshot schema for active account, chain scope, summary balances, module pointers, preferences, provenance, and freshness.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Missing values must remain valid, provenance rules must stay consistent, and a version field should prepare for future schema changes.

## Validation

Build minimal valid snapshots, verify provenance and timestamps for populated fields, and confirm persistence serialization if stored.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
