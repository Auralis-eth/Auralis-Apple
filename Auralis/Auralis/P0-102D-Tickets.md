# P0-102D Tickets And Session Handoff

## Summary

Show the last 5 to 10 receipts on Home with summary, status icon, timestamp, and navigation into receipt detail or the full receipts list.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Use bounded queries for large volumes and ensure the preview reflects active account scope or labels mixed scope clearly.

## Validation

Generate receipts, verify preview updates, open detail from a preview row, open the full receipts list, and switch accounts to confirm the preview updates.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
