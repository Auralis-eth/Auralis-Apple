# P0-462 Tickets And Session Handoff

## Summary

Create the token detail screen for native and ERC-20 assets with provenance, freshness, safe copy, and explorer links.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Adapt the UI for native assets with no contract, unknown decimals, and invalid or empty contract addresses.

## Validation

Open from the token list, log copy and explorer actions, and verify provenance badges match the underlying source.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
