# P0-501 Downstream Dependency Report

This document replaces the old step-by-step execution log for `P0-501`.

`P0-501` is complete in code. This file is now a dependency-facing report for later tickets that build on top of the Phase 0 receipt system.

## Ticket Outcome

`P0-501` delivered the Phase 0 receipt foundation:

- general-purpose receipt contract
- SwiftData-backed receipt persistence
- append-only store behavior
- explicit caller-provided correlation IDs for multi-step flows
- sanitization before persistence
- JSON export as one array payload
- explicit full receipt reset

## What Downstream Tickets Can Rely On

The following behaviors are now treated as stable Phase 0 contracts:

- receipt storage is broad across the app, not account-only
- receipt persistence is SwiftData-backed
- the persisted receipt model is `StoredReceipt`
- receipt payloads are persisted only after sanitization
- sanitization in `P0-501` covers only:
  - raw RPC URL fields
  - raw error string fields
- `ReceiptStore` is append-only by public API shape:
  - append
  - bounded latest reads
  - bounded correlation reads
  - export all
  - full reset
- no mutable update API exists
- no single-receipt delete API exists
- correlation IDs are caller-provided only
- lower layers do not auto-generate correlation IDs
- normal reads are bounded and sorted newest-first using `createdAt` then `sequenceID`
- export is deterministic and sorted oldest-first using `createdAt` then `sequenceID`
- reset is an explicit full wipe, not a convenience delete helper
- account add, select, and remove flows can emit real persisted receipts through the account seam
- one real multi-step networking flow already emits correlated receipts:
  - `NFTService` refresh orchestration
  - `NFTFetcher` fetch work
  - persistence completion or failure follow-up

## Main Seams For Dependent Tickets

These are the primary integration points other tickets should use instead of reintroducing direct persistence logic:

- [`Auralis/Auralis/Receipts/ReceiptContracts.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Receipts/ReceiptContracts.swift)
- [`Auralis/Auralis/DataModels/StoredReceipt.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/DataModels/StoredReceipt.swift)
- [`Auralis/Auralis/Receipts/SwiftDataReceiptStore.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Receipts/SwiftDataReceiptStore.swift)
- [`Auralis/Auralis/Receipts/DefaultReceiptPayloadSanitizer.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Receipts/DefaultReceiptPayloadSanitizer.swift)
- [`Auralis/Auralis/Receipts/ReceiptResetService.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Receipts/ReceiptResetService.swift)
- [`Auralis/Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift)
- [`Auralis/Auralis/Networking/NFTRefreshEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTRefreshEventRecorder.swift)
- [`Auralis/Auralis/Networking/NFTService.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTService.swift)
- [`Auralis/Auralis/Networking/NFTFetcher.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTFetcher.swift)

## Specifically Relevant To Downstream Receipt Work

Later tickets should build on these facts rather than reopening `P0-501` design decisions:

- `ReceiptPayload` is the persisted/export-safe payload boundary
- `RawReceiptPayload` exists for unsanitized input at orchestration edges
- `DefaultReceiptPayloadSanitizer` is the Phase 0 redaction authority
- `SwiftDataReceiptStore` owns persistence, ordering, export, and full reset
- product-specific seams translate domain events into generic receipts
- the account domain already plugs into receipts through `AccountEventRecorder`
- the networking refresh flow already demonstrates explicit correlation-ID threading

## UI And Product Surfaces Already Wired To Receipt Seams

Later tickets should assume these surfaces already use the receipt-backed account seam or the correlated refresh path:

- [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
- [`Auralis/Auralis/Aura/Auth/QRScannerView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/QRScannerView.swift)
- [`Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift)
- [`Auralis/Auralis/Aura/MainAuraView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraView.swift)
- [`Auralis/Auralis/Aura/Newsfeed/EmptyNewsFeedView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Newsfeed/EmptyNewsFeedView.swift)
- [`Auralis/Auralis/Aura/Newsfeed/NewsFeedListView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Newsfeed/NewsFeedListView.swift)
- [`Auralis/Auralis/Aura/Newsfeed/NewsFeedView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Newsfeed/NewsFeedView.swift)

## Validation Status

The `P0-501` foundation has been validated in code:

- `ReceiptContractTests` lock the append-only contract shape, payload boundary, and receipt record fields
- `StoredReceiptTests` cover persisted field round-tripping and relaunch-style persistence across container recreation
- `ReceiptStoreTests` cover append behavior, bounded reads, deterministic export, reset, and sequence-based ordering
- `ReceiptSanitizerTests` cover recursive redaction for the locked Phase 0 fields only
- `AccountReceiptRecorderTests` cover real persisted receipts for add/select/remove account flows
- `NFTServiceReceiptTests` cover one correlated multi-step flow with a caller-provided correlation ID
- `ReceiptResetServiceTests` cover explicit destructive reset behavior through the dedicated reset seam
- targeted receipt validation tests passed
- full project build succeeded

## Known Deferred Or Out-Of-Scope Areas

Dependent tickets should not assume these are solved by `P0-501`:

- receipt browsing UI
- receipt deep-link handling beyond the current safe-fail behavior
- privacy rules beyond raw RPC URL and raw error-string redaction
- module or target separation for receipts and storage
- compile-time enforcement of dependency direction
- repo-wide standardized logger abstractions
- broader local-data reset beyond the receipt store itself
- policy or retention rules beyond append-only plus explicit full reset

## Recommended Read Order For Dependent Tickets

1. [`P0-501-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-501-Strategy.md)
2. [`Auralis/Auralis/Receipts/ReceiptContracts.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Receipts/ReceiptContracts.swift)
3. [`Auralis/Auralis/DataModels/StoredReceipt.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/DataModels/StoredReceipt.swift)
4. [`Auralis/Auralis/Receipts/SwiftDataReceiptStore.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Receipts/SwiftDataReceiptStore.swift)
5. [`Auralis/Auralis/Receipts/DefaultReceiptPayloadSanitizer.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Receipts/DefaultReceiptPayloadSanitizer.swift)
6. [`Auralis/Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift)
7. [`Auralis/Auralis/Networking/NFTRefreshEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTRefreshEventRecorder.swift)
8. [`Auralis/Auralis/Networking/NFTService.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTService.swift)
9. [`Auralis/Auralis/Networking/NFTFetcher.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTFetcher.swift)
10. [`Auralis/AuralisTests/ReceiptStoreTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/ReceiptStoreTests.swift)
11. [`Auralis/AuralisTests/AccountReceiptRecorderTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/AccountReceiptRecorderTests.swift)
12. [`Auralis/AuralisTests/NFTServiceReceiptTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/NFTServiceReceiptTests.swift)

## Rule For Future Tickets

If a later ticket depends on `P0-501`, it should extend the existing receipt seams and locked contracts rather than:

- writing `StoredReceipt` rows directly from views
- inventing ad hoc sanitization in random callers
- auto-generating correlation IDs in lower layers
- adding mutable update helpers to receipt persistence
- adding partial delete helpers that undermine the append-only model
- treating reset as anything other than an explicit full-store wipe

