# P0-403 Strategy: Context inspector UI

## Status

Blocked

## Ticket

Add the Why-am-I-seeing-this inspector with scope, provenance, freshness, and links to related receipts.

## Dependencies

P0-101C, P0-402, P0-503

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Inspector should still work with no receipts, large details need collapse behavior, and stale offline context must be labeled clearly.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Open from major screens, verify freshness and provenance display against real cache state, and navigate into linked receipt detail.
