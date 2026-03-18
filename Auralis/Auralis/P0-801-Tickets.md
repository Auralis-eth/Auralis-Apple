# P0-801 Tickets And Session Handoff

## Summary

Provide a deterministic demo dataset and safe offline behavior so the app remains demoable and usable without network connectivity.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Keep demo mode distinct from real data, handle first-run offline with no cache, and ensure demo content remains consistent across launches.

## Validation

Use airplane mode on fresh install and after cache exists, and verify the demo dataset behaves consistently across relaunches.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
