# P0-402 Tickets And Session Handoff

## Summary

Implement ContextService as the only UI entry point for scoped context, coordinating provider reads, cache use, snapshot assembly, and receipts.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Cancel and isolate rapid account switches, coalesce concurrent context requests, and return partial snapshots when substeps fail.

## Validation

Request context from UI, observe cached-then-refresh updates, switch active account without stale overwrites, and verify UI has no direct provider access.

## Completion Summary

- added a real `ContextService` seam as the shell UI entry point
- removed direct `ContextSource` usage from `MainTabView` and the context inspector
- gave the service cached snapshot ownership for the active shell context
- coalesced duplicate in-flight context requests for the same scope
- prevented stale context overwrites during rapid account switches with generation-based isolation
- covered coalescing and rapid-switch protection with focused tests

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
