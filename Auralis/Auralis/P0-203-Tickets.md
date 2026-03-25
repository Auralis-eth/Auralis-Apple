# P0-203 Dependency Report

This document records the dependency posture, delivered scope, deferred scope, and validation state for `P0-203`.

`P0-203` is complete for its planned first pass.

## Ticket

JIRA: `P0-203`

Goal:

- support ENS forward resolution in account-entry flow before account persistence
- support best-effort reverse lookup for active-account display
- keep caching, freshness, and receipt semantics inside Auralis-owned seams instead of provider-specific models

## Dependency Status

Satisfied dependencies:

- `P0-201` Account model + persistence
- `P0-301` Provider abstraction groundwork
- `P0-302` Read-only provider support
- `P0-502` Receipt sanitization and append-only store contract

Planning rule preserved by this implementation:

- ship the first slice behind an `ENSResolving` seam
- treat Argent `web3.swift` as an adapter choice, not an app architecture choice
- keep direct Ethereum RPC or light-node work deferred as a backend swap

## Delivered ENS Layer

Primary delivered file:

- [`Auralis/Auralis/Networking/ENSResolutionService.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/ENSResolutionService.swift)

Supporting integration files:

- [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
- [`Auralis/Auralis/Aura/Auth/GatewayView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/GatewayView.swift)
- [`Auralis/Auralis/Aura/Home/ProfileCardView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/ProfileCardView.swift)
- [`Auralis/Auralis/AppServices.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/AppServices.swift)

Delivered ENS behaviors:

- `ENSResolving` is the app-facing seam for forward cache reads, reverse cache reads, forward resolution, and reverse lookup
- the live adapter uses `EthereumHttpClient` and `EthereumNameService` inside the networking layer only
- ENS names and addresses are normalized into one canonical app comparison format
- reverse lookup is only shown when reverse-then-forward verification succeeds
- forward and reverse results are cached with freshness metadata and stale-cache fallback behavior
- account entry now resolves ENS before persistence
- the active account surface performs best-effort reverse ENS display
- ENS receipts exist for cache hit, lookup start, success, mapping change, and failure
- changed ENS mappings no longer silently overwrite cached identity; the app requires explicit confirmation before persisting the updated address
- rapid repeated ENS submits do not let stale requests overwrite the latest input state

## Production Mounting

Auth entry integration:

- [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)

Home identity display integration:

- [`Auralis/Auralis/Aura/Home/ProfileCardView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/ProfileCardView.swift)

Resolver factory mount:

- [`Auralis/Auralis/AppServices.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/AppServices.swift)

Why this shape matters for later tickets:

- views depend on Auralis-owned value types instead of `web3.swift` model types
- the provider choice is isolated to the live factory and adapter boundary
- future tickets can swap backend implementation without rewriting auth or home UI

## Cache And Safety Contract

The first-pass ENS contract established by `P0-203` is:

- fresh cached forward results are returned before hitting the provider again
- stale forward cache is used when refresh fails instead of dropping identity data
- stale reverse cache is only used when the cached name was previously forward-verified
- reverse names are never trusted blindly
- changed forward mappings are surfaced as an explicit app-level condition instead of an automatic overwrite
- receipt payloads stay sanitized and avoid leaking provider secrets or raw library internals

## Deferred By Design

Still owned by later tickets:

- direct Ethereum RPC or light-node ENS implementation
- richer ENS UI beyond the current auth confirmation and profile display path
- chain-agnostic naming systems beyond `.eth`
- broader UI automation or on-device validation coverage for ENS-specific flows

## Validation

Completed validation:

- the project built successfully after the ENS integration
- focused ENS tests passed for fresh-cache reuse, stale-cache fallback, reverse verification, mapping-change surfacing, and ENS receipt emission

Relevant automated coverage:

- [`Auralis/AuralisTests/ENSResolutionServiceTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/ENSResolutionServiceTests.swift)
- [`Auralis/AuralisTests/ENSEventRecorderTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/ENSEventRecorderTests.swift)

Residual validation note:

- the last full-suite run had one unrelated failing test in [`Auralis/AuralisTests/NFTServiceReceiptTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/NFTServiceReceiptTests.swift):296; that failure is outside `P0-203` scope and does not come from the ENS files

## Completion Summary

`P0-203` is complete for the planned first pass because:

- ENS resolution is now a real production seam rather than a deferred validation error
- the first implementation stays provider-agnostic at the app boundary
- the critical safety rules are enforced: cancellation, stale-cache preference, reverse verification, and non-silent mapping changes
- receipts and tests now cover the important ENS flow contracts future tickets will depend on
