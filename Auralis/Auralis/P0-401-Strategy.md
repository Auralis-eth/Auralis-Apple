# P0-401 Strategy: Context schema v0 (graph-lite)

## Status

Blocked

## Ticket

Define the scoped ContextSnapshot schema for active account, chain scope, summary balances, module pointers, preferences, provenance, and freshness.

## Dependencies

P0-201, P0-204, P0-302

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Missing values must remain valid, provenance rules must stay consistent, and a version field should prepare for future schema changes.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Build minimal valid snapshots, verify provenance and timestamps for populated fields, and confirm persistence serialization if stored.
