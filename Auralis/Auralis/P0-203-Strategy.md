# P0-203 Strategy: ENS resolution + reverse lookup (best-effort)

## Status

Ready

## Ticket

Support ENS forward resolution and best-effort reverse lookup with caching, refresh behavior, and receipt emission for changes and lookups.

## Dependencies

P0-201, P0-301, P0-302, P0-502

## Strategy

- Keep the implementation narrow and phase-correct.
- Ship with the installed Argent `web3.swift` ENS support instead of inventing new contract plumbing in this ticket.
- Back the ENS service with a `web3.swift` `EthereumHttpClient` and `EthereumNameService`.
- Hide the library behind an injected ENS service seam so downstream code does not couple to `web3.swift` types.
- Treat ENS as Ethereum-mainnet identity data even when the active app chain is another EVM chain.
- Preserve a clean migration path to a later direct Ethereum RPC or light-node-backed implementation.
- Validate the named edge cases before broadening scope.

## Chosen Delivery Shape

- Introduce an `ENSResolving` service seam with forward resolve, reverse lookup, and refresh APIs.
- Start with a `web3.swift`-backed implementation behind that seam.
- Require reverse lookup to be treated as best-effort display data and forward-verified before trust.
- Add cache entries with timestamps, provenance, and stale/offline behavior using the `P0-302` freshness contract.
- Emit receipts for cache hit, lookup start, network success, mapping change, and failure paths.
- Use `ResolutionMode.allowOffchainLookup` so modern ENS names that rely on offchain lookup continue to resolve.
- Keep the Auralis-facing contract independent from `web3.swift` result types and errors.

## Implementation Blueprint

### App-facing seam

- Add an `ENSResolving` protocol under `Networking/` or a nearby app service boundary.
- Keep its API app-native and async-first.
- Preferred initial shape:
  - `resolveAddress(forENS name: String) async throws -> ENSForwardResolution`
  - `reverseLookup(address: String) async throws -> ENSReverseResolution`
  - `cachedForwardResolution(forENS name: String) -> ENSForwardResolution?`
  - `cachedReverseResolution(forAddress address: String) -> ENSReverseResolution?`

### App-native result types

- Use small Auralis-owned value types instead of `web3.swift` models.
- Forward result should at minimum contain:
  - normalized ENS name
  - normalized resolved address
  - resolution source / provenance
  - fetched-at timestamp
  - stale flag or freshness metadata
- Reverse result should at minimum contain:
  - normalized address
  - resolved ENS name
  - whether the reverse result was forward-verified
  - resolution source / provenance
  - fetched-at timestamp
  - stale flag or freshness metadata

### Concrete adapter

- Add a `Web3EthereumNameServiceResolver` implementation in `Networking/`.
- Internally build:
  - `EthereumHttpClient(url: rpcURL, network: .mainnet)`
  - `EthereumNameService(client: client)`
- Keep `web3.swift` imports isolated to that file or narrow adapter layer.

### API call flow

- Forward resolve:
  - normalize and validate ENS input
  - create `EthereumNameService`
  - call `resolve(ens:mode:)` with `.allowOffchainLookup`
  - convert returned `EthereumAddress` into canonical lowercased `0x...` string for app storage and comparisons
- Reverse resolve:
  - normalize and validate address input
  - call `resolve(address:mode:)` with `.allowOffchainLookup`
  - immediately forward-resolve the returned name
  - only mark the reverse name trusted if the forward result matches the original normalized address

### Ownership boundaries

- `web3.swift` owns RPC and ENS contract mechanics.
- Auralis owns:
  - normalization
  - cache storage and TTL behavior
  - stale/offline behavior
  - cancellation rules
  - receipt emission
  - user-facing error mapping

## Likely File Touch Points

- `Auralis/Auralis/Networking/ReadOnlyProviderSupport.swift`
  to extend endpoint configuration with the RPC URL used by the ENS adapter if needed
- `Auralis/Auralis/Networking/Secrets.swift`
  only if ENS needs a distinct provider key path beyond the existing configuration
- `Auralis/Auralis/Accounts/AccountStore.swift`
  to stop treating ENS as unsupported and to route ENS entry through the resolver
- `Auralis/Auralis/Aura/Auth/AddressEntryView.swift`
  to support ENS entry feedback and async resolution flow
- `Auralis/Auralis/Aura/Auth/QRScannerView.swift`
  only if scanned ENS names should be accepted in Phase 0
- `Auralis/Auralis/Aura/Home/ProfileCardView.swift`
  or another account-summary surface for best-effort reverse ENS display
- `Auralis/Auralis/Receipts/`
  for ENS lookup receipt integration

## Testing Targets

- unit tests for ENS name validation and address normalization
- unit tests for reverse-then-forward verification behavior
- unit tests for cache hit, stale cache, and refresh failure fallback
- adapter tests with stubbed `ENSResolving` seam at app level
- optional focused integration tests around the `web3.swift` adapter if network stubbing is practical

## Library Notes

- The installed Argent package already includes `EthereumNameService.resolve(ens:mode:)` and `resolve(address:mode:)`.
- `web3.swift` ships resolver, wildcard, and offchain lookup support out of the box.
- Its built-in ENS registry helper only defaults cleanly for `mainnet` and `goerli`, so the Auralis Phase 0 path should explicitly treat ENS as Ethereum mainnet identity data.
- If testnet ENS support becomes necessary later, pass the registry address explicitly instead of teaching the app layer about network quirks.

## Deferred Infrastructure Direction

- The long-term backend may move to direct Ethereum RPC or a lighter node strategy aligned with Ethereum's future roadmap.
- That later swap must not require rewriting account entry, chrome, Home, or search flows.
- The service contract, cache contract, and receipt vocabulary chosen here should survive that backend replacement unchanged.

## Key Risk

Slow ENS resolution must be cancellable, changed ENS mappings must not silently overwrite, offline mode must prefer cached data, and library-first delivery must not leak `web3.swift` types or network quirks into the app layer.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The first shipped implementation uses `web3.swift` only behind the ENS service seam.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Add account via ENS, display reverse ENS when available, refresh ENS with receipts, verify cached stale ENS in offline mode, and confirm the UI layer remains provider-agnostic.
