# P0-301 Tickets And Session Handoff

## Summary

Create the injected, read-only provider interface for chain-aware balance and metadata fetches with centralized RPC configuration.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum injected provider slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record the remaining downstream blockers explicitly.

## Critical Edge Case

Handle rate limits, slow responses, unexpected payload shapes, and future provider swapping without leaking direct calls into UI.

## Validation

Fetch native balance on a known chain, surface structured failures, enforce use through Context Service, and reflect provider config changes on restart or refresh.

## Handoff Rule

Do not build throwaway scaffolding. It is acceptable to land injectable provider seams and centralized config now, but any missing context-service ownership, freshness behavior, or token-surface consumers must be recorded as deferred follow-on work.
