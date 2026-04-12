# P0-501 Tickets And Session Handoff

## Summary

Deliver the append-only Phase 0 receipt foundation with sanitized persistence, bounded reads, export, reset, and explicit caller-provided correlation IDs.

## Ticket Status

Completed for the current receipt-foundation baseline.

## Execution Checklist

### 1. Establish the receipt contract

- [x] Define the persisted receipt model and append-only store shape.
- [x] Keep payload sanitization explicit and centralized.
- [x] Preserve caller-provided-only correlation ID ownership.

### 2. Implement the persistence layer

- [x] Add the SwiftData-backed append-only receipt store.
- [x] Add bounded latest reads and bounded correlation reads.
- [x] Add deterministic export and explicit full reset.

### 3. Integrate the first product seams

- [x] Plug account events into real persisted receipts through `AccountEventRecorder`.
- [x] Plug one real correlated networking flow into the receipt system.
- [x] Keep product-specific recorders thin and receipt persistence generic.

### 4. Validate the vertical slice

- [x] Verify append-only behavior, ordering, export, reset, and sanitization.
- [x] Verify account flows emit real receipts.
- [x] Verify one multi-step network flow shares a caller-owned correlation ID.

## Implementation Notes

- Core receipt contracts live in `Auralis/Auralis/Receipts/ReceiptContracts.swift`.
- Persistence is backed by `Auralis/Auralis/DataModels/StoredReceipt.swift` and `Auralis/Auralis/Receipts/SwiftDataReceiptStore.swift`.
- Sanitization is centralized in `Auralis/Auralis/Receipts/DefaultReceiptPayloadSanitizer.swift`.
- Reset is explicit through `Auralis/Auralis/Receipts/ReceiptResetService.swift`.
- Account and networking integrations already flow through `AccountEventRecorder` and `NFTRefreshEventRecorder`.

## Validation Notes

- `AuralisTests/ReceiptContractTests.swift` locks the append-only contract shape and receipt fields.
- `AuralisTests/StoredReceiptTests.swift` covers persisted field round-tripping and relaunch-style persistence.
- `AuralisTests/ReceiptStoreTests.swift` covers append behavior, bounded reads, deterministic export, reset, and sequence ordering.
- `AuralisTests/ReceiptSanitizerTests.swift` covers the locked Phase 0 redaction rules.
- `AuralisTests/AccountReceiptRecorderTests.swift` covers persisted account-flow receipts.
- `AuralisTests/NFTServiceReceiptTests.swift` covers a correlated multi-step refresh flow.
- `AuralisTests/ReceiptResetServiceTests.swift` covers explicit destructive reset behavior.
- The dependency report records targeted receipt validation tests passing plus a successful full project build.

## Critical Edge Case

Sanitization must happen before persistence or the append-only store becomes an append-only leak.

## Handoff Rule

If a later ticket needs more receipt UI or privacy behavior, extend the existing receipt seams instead of weakening the append-only contract or inventing ad hoc sanitization paths.
