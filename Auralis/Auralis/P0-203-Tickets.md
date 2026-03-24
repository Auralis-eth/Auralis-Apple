# P0-203 Tickets And Session Handoff

## Summary

Support ENS forward resolution and best-effort reverse lookup with caching, refresh behavior, and receipt emission for changes and lookups.

The first production slice should use the installed Argent `web3.swift` ENS support behind a provider-agnostic service seam. Direct Ethereum RPC or light-node work is explicitly deferred as a backend swap, not mixed into this first delivery.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Define the `ENSResolving` seam and cache contract before wiring any library-specific client.
3. Implement the `web3.swift`-backed forward and reverse lookup slice behind that seam.
4. Cover the stated edge cases before expanding scope.
5. Run the ticket-specific validation path and record any blockers.

## Concrete Build Steps

1. Add Auralis-owned ENS request/result types and the `ENSResolving` protocol.
2. Add the `web3.swift` adapter using `EthereumHttpClient` and `EthereumNameService`.
3. Normalize ENS and address inputs into one canonical app comparison format.
4. Add reverse-then-forward verification so reverse names are never trusted blindly.
5. Add cache entries and freshness metadata for both forward and reverse lookups.
6. Wire account-entry flow to resolve ENS before persistence.
7. Wire best-effort reverse name display for the active account surface.
8. Add receipt events for cache hit, lookup start, success, mapping change, and failure.
9. Validate offline stale-cache behavior and rapid-cancel behavior.

## Critical Edge Case

Slow ENS resolution must be cancellable, changed ENS mappings must not silently overwrite, offline mode must prefer cached data, and reverse results must not be trusted without verification.

## Validation

Add account via ENS, display reverse ENS when available, refresh ENS with receipts, verify cached stale ENS in offline mode, and confirm that no UI surface depends on `web3.swift`-specific models.

Specific checks:

- entering `vitalik.eth` resolves to a canonical `0x...` address before account persistence
- reverse lookup for a known address shows a name only when forward verification succeeds
- cached ENS data survives refresh failure and is marked stale instead of disappearing
- rapid ENS edits do not let older results overwrite newer input state
- receipt payloads do not expose provider secrets or raw library internals

## Handoff Rule

Do not let the temporary library choice leak into app architecture. If a later direct RPC or light-node implementation cannot slot into the same ENS service seam, the first slice was shaped incorrectly.
