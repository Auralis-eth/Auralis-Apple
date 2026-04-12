# P0-601 Tickets And Session Handoff

## Summary

Implement the global Observe-only mode state, display it in chrome, persist it in app state, and include it in receipts.

## Ticket Status

Completed for the current Phase 0 mode-ownership slice.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Avoid incorrect mode state after restore and avoid confusing users with disabled future mode-switch UI.

## Validation

Mode badge always shows Observe, receipts include mode=Observe, and any execute placeholder is denied and logged.

## Completion Summary

- formalized `ModeState` as the global mode owner
- locked Phase 0 mode to `Observe`
- routed denied placeholder actions through `ExecutePolicyGate`
- added receipt coverage for Observe-mode denials
- kept the chrome mode badge backed by the shared mode state

## Handoff Rule

Treat this ticket as complete for Phase 0. Use `P0-602` for broader policy-gate rollout rather than reopening the Observe-mode ownership decision.
