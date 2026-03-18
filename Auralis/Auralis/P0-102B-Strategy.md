# P0-102B Strategy: Active account summary card

## Status

Blocked

## Ticket

Create the Home summary card for identity, chain scope, balance, and freshness with copy and inspector/account-detail actions.

## Dependencies

P0-102A, P0-203, P0-301, P0-302, P0-501

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

ENS fallback, unavailable balance, and stale cached balances must read clearly without implying broken state.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Copy address logs a receipt, balance refresh updates freshness, ENS fallback works, and forced stale cache timestamps update the label.
