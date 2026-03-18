# P0-702 Tickets And Session Handoff

## Summary

Treat remote metadata as untrusted, label it where displayed, and ensure untrusted strings cannot create app intents beyond normal navigation.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Handle control characters, spoofed domains, and oversized descriptions without breaking layout or implying trust.

## Validation

Show untrusted badges, ensure metadata cannot trigger behavior, require explicit interaction for external links, and sanitize control characters safely.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
