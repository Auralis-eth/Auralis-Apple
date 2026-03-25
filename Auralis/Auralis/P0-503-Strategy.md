# P0-503 Strategy: Receipts UI (timeline + filters)

## Status

Completed

## Ticket

Build the receipts timeline with filtering, search, pagination, and structured receipt detail with related-receipt links by correlation ID.

## Outcome

- Shipped the receipts tab timeline in the app shell with search, status/actor/scope filters, incremental pagination, and a structured detail view.
- Scoped receipt visibility, counts, and related-receipt navigation to the active wallet and chain instead of labeling an unscoped archive.
- Persisted wallet/chain scope hints on receipt rows and added payload-based fallback so older local receipts still participate in scoped filtering.
- Verified the ticket with targeted unit coverage for timeline state, stored-receipt scope fallback, and receipt event logging.

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

## Validation Result

- `BuildProject` passed on the `Auralis` scheme.
- Targeted tests passed for `ReceiptTimelineStateTests`, `StoredReceiptTests`, and `ReceiptEventLoggerTests`.
- Remaining validation is limited to on-device/manual product testing.
