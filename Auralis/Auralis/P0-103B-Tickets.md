# P0-103B Tickets And Session Handoff

## Summary

Implement deterministic search query classification for ENS, addresses, contracts, token symbols, names, and collections with inline detection feedback.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Mixed input, ENS-like invalid strings, ambiguous addresses, and very short token symbols must produce deterministic, non-misleading behavior.

## Validation

Verify ENS detection, address detection, token lookup matches, and invalid address rejection without network calls or receipts.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
