# P0-301 Tickets And Session Handoff

## Summary

Create the injected, read-only provider interface for chain-aware balance and metadata fetches with centralized RPC configuration.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Handle rate limits, slow responses, unexpected payload shapes, and future provider swapping without leaking direct calls into UI.

## Validation

Fetch native balance on a known chain, surface structured failures, enforce use through Context Service, and reflect provider config changes on restart or refresh.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
