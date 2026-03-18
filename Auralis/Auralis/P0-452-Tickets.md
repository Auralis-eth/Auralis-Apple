# P0-452 Tickets And Session Handoff

## Summary

Build read-only music collection and item details with explorer links, copy actions, local pin or favorite actions, and provenance labels.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Missing artwork, long metadata, and unavailable explorer links must degrade safely without suggesting trust.

## Validation

Navigate collection to item detail and back, log copy and explorer actions, and label metadata as untrusted where required.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
