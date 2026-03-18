# P0-102D Strategy: Recent activity preview (receipts snippet)

## Status

Blocked

## Ticket

Show the last 5 to 10 receipts on Home with summary, status icon, timestamp, and navigation into receipt detail or the full receipts list.

## Dependencies

P0-102A, P0-501, P0-503

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Use bounded queries for large volumes and ensure the preview reflects active account scope or labels mixed scope clearly.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Generate receipts, verify preview updates, open detail from a preview row, open the full receipts list, and switch accounts to confirm the preview updates.
