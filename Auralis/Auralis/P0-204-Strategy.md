# P0-204 Strategy: Chain scope settings per account (v0)

## Status

Blocked

## Ticket

Add per-account chain scope settings that drive Context Builder and downstream library surfaces.

## Dependencies

P0-201, P0-401, P0-402, P0-501

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Prevent empty chain scope, handle out-of-scope detail screens gracefully, and design a list that can grow later.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Persist chain scope per account, trigger context rebuild and receipts on scope change, and verify library surfaces respect the selected scope.
