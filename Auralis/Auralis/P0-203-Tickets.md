# P0-203 Tickets And Session Handoff

## Summary

Support ENS forward resolution and best-effort reverse lookup with caching, refresh behavior, and receipt emission for changes and lookups.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Slow ENS resolution must be cancellable, changed ENS mappings must not silently overwrite, and offline mode must prefer cached data.

## Validation

Add account via ENS, display reverse ENS when available, refresh ENS with receipts, and verify cached stale ENS in offline mode.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
