# P0-203 Strategy: ENS resolution + reverse lookup (best-effort)

## Status

Blocked

## Ticket

Support ENS forward resolution and best-effort reverse lookup with caching, refresh behavior, and receipt emission for changes and lookups.

## Dependencies

P0-201, P0-301, P0-302, P0-502

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Slow ENS resolution must be cancellable, changed ENS mappings must not silently overwrite, and offline mode must prefer cached data.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Add account via ENS, display reverse ENS when available, refresh ENS with receipts, and verify cached stale ENS in offline mode.
