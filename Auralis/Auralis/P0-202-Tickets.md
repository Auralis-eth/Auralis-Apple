# P0-202 Tickets And Session Handoff

## Summary

Validate and normalize EVM addresses early, present them consistently across the UI, and reject invalid formats before persistence.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Trim whitespace, reject non-hex and non-EVM formats, and decide whether ENS in address fields is redirected or rejected.

## Validation

Block invalid addresses, save valid normalized addresses, copy normalized values exactly, and trim pasted whitespace before validation.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
