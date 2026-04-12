# P0-302 Tickets And Session Handoff

## Summary

Implement cache entries with timestamps, TTL policy, stale detection, refresh triggers, and UI-facing last-updated values.

## Ticket Status

Completed for the current freshness-contract slice.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Retain cached data when refresh fails, avoid negative freshness after time shifts, and coalesce duplicate in-flight fetches.

## Validation

Store cache on first fetch, mark stale after TTL expiry, refresh timestamps correctly, and preserve cached stale values on refresh failure with a receipt.

## Completion Summary

- added TTL-backed freshness metadata to the live context source
- updated shell freshness labeling to use stale evaluation instead of ad hoc age-only rules
- exposed TTL in the context inspector for the active slice
- preserved the last successful refresh timestamp and visible error state when a later refresh fails
- coalesced duplicate in-flight NFT refreshes for the same account/chain scope
- covered stale detection, negative-age clamping, retained stale values, and coalescing with focused tests

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
