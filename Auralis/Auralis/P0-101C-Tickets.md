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

Open the inspector from chrome, force stale timestamps, refresh from the inspector freshness section, and switch accounts rapidly without showing duplicated or incorrect context.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.

## Latest Completion Note

- kept the product decision to avoid a dedicated freshness indicator in global chrome
- moved the explicit freshness behavior onto the inspector freshness section instead
- added stale/unknown/no-success refresh affordances there, routed through the main shell refresh path
- preserved the existing chrome entry point instead of inventing a second inspector trigger

## Remaining Note

- if the project later reintroduces a distinct chrome freshness control, that would be a new surface decision rather than a prerequisite for this context-sheet interpretation of `P0-101C`
