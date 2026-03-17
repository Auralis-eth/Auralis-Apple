# P0-501 Tickets And Session Handoff

This document converts the strategy in [`P0-501-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-501-Strategy.md) into execution-oriented steps that can be handed from session to session.

## Scope

`P0-501` implements a broad Phase 0 receipt system:

- general-purpose receipt schema
- append-only local persistence
- caller-provided correlation IDs for multi-step flows
- JSON export as a single array
- full local receipt reset

Phase 0 decisions already locked:

- storage is SwiftData-backed
- receipt scope is broad across the app, not account-only
- correlation IDs are explicit and caller-provided only
- redaction currently covers only:
  - raw RPC URLs
  - raw error strings
- export format is one JSON array
- reset is included now, not deferred
- append-only means no update API and no per-receipt delete API

## Step Plan

### Step 1: Lock the receipt contract

- define the minimum receipt field set
- define the append-only protocol surface
- define export and reset at the contract level
- define sanitization responsibility before persistence

Status:

- completed

Exit criteria:

- the receipt model shape is agreed in code comments or doc comments
- append-only rules are encoded in API shape
- no mutable update path exists

Session notes:

- added receipt contract types under `Auralis/Auralis/Receipts/ReceiptContracts.swift`
- encoded the append-only API as `ReceiptStore` with append, bounded reads, export, and full reset only
- split raw payload input from persisted/export-safe `ReceiptPayload` through `ReceiptPayloadSanitizing`
- added `ReceiptContractTests` to lock the contract shape without starting SwiftData persistence yet

### Step 2: Add the SwiftData receipt model

- add the receipt model under the app’s persisted model area
- include stable identifier, sequence ID, timestamp, event metadata, correlation ID, and sanitized payload storage
- ensure the main model container includes it

Status:

- pending

Exit criteria:

- receipts persist in the same local stack as the app’s other Phase 0 models
- model container builds with the new type included

### Step 3: Implement the append-only store

- add a generic receipt store interface
- implement SwiftData-backed create/read/export/reset behavior
- implement bounded reads and stable ordering using sequence ID fallback

Status:

- pending

Exit criteria:

- normal reads are bounded
- export returns all receipts in deterministic order
- there is still no update or per-item delete path

### Step 4: Add sanitization and export

- implement redaction for raw RPC URLs
- implement redaction for raw error strings
- export receipts as a single JSON array from sanitized persisted payloads

Status:

- pending

Exit criteria:

- sensitive fields covered by this ticket are redacted before persistence
- export JSON is valid and consistent

### Step 5: Replace the no-op account receipt seam

- plug a real receipt-backed implementation into [`Auralis/Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift)
- keep the account domain depending on a seam, not on SwiftData receipt details

Status:

- pending

Exit criteria:

- account add/remove/select flows can emit real receipts
- `AccountStore` still does not own receipt persistence details directly

### Step 6: Add correlated flow support in one orchestration path

- choose one real multi-step flow
- thread a caller-created correlation ID through it
- emit linked receipts across the steps

Good first candidate:

- `NFTService` refresh orchestration into `NFTFetcher` work and follow-on context updates

Status:

- pending

Exit criteria:

- a real multi-step flow emits multiple receipts with the same explicit correlation ID
- no lower layer auto-generates IDs

### Step 7: Add reset support

- implement full receipt reset
- keep reset separate from append-only APIs
- verify reset semantics are explicit and destructive

Status:

- pending

Exit criteria:

- receipts can be fully wiped in one explicit operation
- there is still no partial delete API

### Step 8: Validate end-to-end behavior

- create receipts for basic actions
- relaunch and confirm persistence
- verify append-only API shape
- verify export JSON
- verify reset behavior
- verify sequence-based stable ordering behavior

Status:

- pending

Exit criteria:

- the `P0-501` test plan is covered in code
- build and targeted tests pass

## P0-201 Dependency Input

Read [`P0-201-Dependency-Report.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-201-Dependency-Report.md) before implementing receipt work that touches account flows.

For `P0-501`, that report is the authoritative downstream contract for watch-only account behavior. Treat it as the stable handoff from completed `P0-201`, not as a generic historical ticket note.

The parts that matter most here:

- account add, remove, and select rules already live behind `AccountStore`
- account event logging already has a seam through `AccountEventRecorder`
- logout and fallback-selection semantics are already fixed and should not be redefined during receipt work

## What already exists

- [`Auralis/Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift) already exists as the seam introduced during `P0-201`
- `P0-201` intentionally kept receipt logging behind a no-op boundary so `P0-501` could land later without reopening the account architecture
- no receipt model or store exists yet, so `P0-501` can still shape the core contract cleanly

## Concrete Implementation Notes

Implementation discipline for pre-`P0-701` work:

- keep the receipt store behind a small protocol
- inject it into service seams instead of reaching for global statics
- keep SwiftUI views out of receipt persistence details
- prefer recorder facades for product-specific events

Good initial integration order:

1. land the generic receipt model and store
2. replace the account no-op seam with a real receipt-backed recorder
3. add one correlated multi-step flow in networking/service orchestration
4. add export and reset validation

## What Requires P0-701

These items should be called out as not solved by `P0-501` alone:

- compile-time module or target separation between UI, Context, Providers, Policy, Receipts, and Storage
- enforced prohibition on UI importing Providers
- repo-wide dependency direction guarantees through code structure
- stronger standardized logger interfaces across the entire app surface
- true module-visibility controls preventing helper creep across layers

`P0-501` should prepare for those boundaries by staying injectable and narrow, but it should not pretend to enforce them.

## Suggested Files To Read First

- [`Auralis/Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift)
- [`Auralis/Auralis/Accounts/AccountStore.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountStore.swift)
- [`P0-201-Dependency-Report.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-201-Dependency-Report.md)
- [`Auralis/Auralis/Networking/NFTService.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTService.swift)
- [`Auralis/Auralis/Networking/NFTFetcher.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTFetcher.swift)
- [`Auralis/Auralis/AuralisApp.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/AuralisApp.swift)
- [`P0-501-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-501-Strategy.md)

## Validation Plan

- receipt model diagnostics clean
- receipt store diagnostics clean
- targeted receipt-store tests pass
- account recorder integration tests pass
- at least one correlated multi-step flow test passes
- export JSON validation test passes
- reset test passes
- full project build succeeds

## Next Session Handoff

Start with Step 2.

Do not do yet:

- broad repo-wide logger refactors
- target/package/module splitting masquerading as `P0-501`
- UI-facing receipt browsers unless needed for validation
- privacy requirements beyond the already locked raw-URL and raw-error redaction

Execution rule:

- implement one step
- add or update tests
- run diagnostics
- run targeted tests
- run a full build
- update this document before moving to the next step
