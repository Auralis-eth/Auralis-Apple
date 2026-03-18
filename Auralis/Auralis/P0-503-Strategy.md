# P0-503 Strategy: Receipts UI (timeline + filters)

## Status

Blocked

## Ticket

Build the receipts timeline with filtering, search, pagination, and structured receipt detail with related-receipt links by correlation ID.

## Dependencies

P0-501, P0-101A, P0-101E

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Handle empty state, large volumes, and default filter clarity when account scope changes.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Load and filter the list, open receipt detail and related receipts, search by key fields, and validate empty and large list behavior.
