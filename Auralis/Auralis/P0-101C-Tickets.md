# P0-101C Tickets And Session Handoff

## Summary

Wire the chrome freshness and scope UI to Context Builder, support stale detection, and open Context Inspector from the chrome with consistent refresh behavior.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Context build failure, TTL expiry mid-navigation, and rapid account switching must not produce spinner loops, stale overwrites, or incorrect scope display.

## Validation

Tap freshness pill to open inspector, force stale timestamps, refresh from chrome, and switch accounts rapidly without showing duplicated or incorrect context.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
