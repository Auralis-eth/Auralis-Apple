# P0-101D Strategy: Global error + empty-state patterns (shell-level)

## Status

Partially blocked

## Ticket

Create shared shell-level empty and error patterns for first-run, provider failure, no receipts, and empty library states.

## Dependencies

P0-101E

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Avoid banner stacking, preserve partial cached content on refresh failure, and clearly label demo content on first-run paths.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Launch with no accounts, disable network while cached data exists, open receipts with none, and verify the library empty state offers only safe actions.
