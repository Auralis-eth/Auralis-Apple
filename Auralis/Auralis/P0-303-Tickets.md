# P0-303 Tickets And Session Handoff

## Summary

Define unified provider and degraded-mode errors so the app stays navigable through offline, parsing, and rate-limit failures.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Partial failures must not blank whole screens, retry loops must be bounded, and rapid user refreshes must be throttled with feedback.

## Validation

Simulate offline and rate-limit conditions, verify receipts for failures, and confirm partial UI remains available without crashes.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
