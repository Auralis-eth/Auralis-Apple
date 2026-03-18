# P0-103C Strategy: Resolution pipeline (local-first, read-only)

## Status

Blocked

## Ticket

Build the cancellable local-first resolution pipeline with optional ENS or on-chain fallback and receipt logging for all network activity.

## Dependencies

P0-103B, P0-302, P0-301, P0-502

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Rapid typing must cancel old work, ENS changes over time must be timestamped and logged, and offline mode must preserve local results.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Local results appear instantly, ENS resolution is cancellable and logged, offline mode degrades gracefully, and stale search results do not bleed through after rapid typing.
