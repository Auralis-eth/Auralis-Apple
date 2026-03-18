# P0-302 Tickets And Session Handoff

## Summary

Implement cache entries with timestamps, TTL policy, stale detection, refresh triggers, and UI-facing last-updated values.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Retain cached data when refresh fails, avoid negative freshness after time shifts, and coalesce duplicate in-flight fetches.

## Validation

Store cache on first fetch, mark stale after TTL expiry, refresh timestamps correctly, and preserve cached stale values on refresh failure with a receipt.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
