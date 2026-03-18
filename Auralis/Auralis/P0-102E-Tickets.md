# P0-102E Tickets And Session Handoff

## Summary

Implement the first-run Home experience with add-account or ENS entry CTA and optional demo entry, then transition directly into the full dashboard.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Invalid input should not leave onboarding, and provider failure after adding an account must still land the user in a usable shell.

## Validation

Fresh install shows CTA, valid address lands on Home without relaunch, invalid address is blocked clearly, and demo mode stays visibly reversible.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
