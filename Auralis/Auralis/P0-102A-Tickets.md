# P0-102A Tickets And Session Handoff

## Summary

Build the OS-level Home dashboard with active account summary, module tiles, recent activity preview, and quick links.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Show onboarding when no account exists, keep the dashboard navigable when context is unavailable, and handle empty recent activity cleanly.

## Validation

Render with demo or offline data, render with real cached context, verify tile routing, and open receipt details from recent activity.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
