# P0-303 Tickets And Session Handoff

## Summary

Define unified provider and degraded-mode errors so the app stays navigable through offline, parsing, and rate-limit failures.

## Ticket Status

Completed for the current degraded-mode slice.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Partial failures must not blank whole screens, retry loops must be bounded, and rapid user refreshes must be throttled with feedback.

## Validation

Simulate offline and rate-limit conditions, verify receipts for failures, and confirm partial UI remains available without crashes.

## Completed Slice

- introduced a typed `NFTProviderFailure` contract and degraded/blocking presentation mapping for the active NFT refresh path
- updated newsfeed empty and cached-content surfaces to stay navigable without branching on raw localized provider errors
- recorded structured provider failure metadata in NFT refresh failure receipts
- validated with focused `NFTServiceReceiptTests` plus a successful project build

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
