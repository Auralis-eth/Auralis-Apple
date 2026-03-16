# P0-501 Strategy: Receipt Schema + Append-Only Store

## Ticket

`P0-501` defines a broad Phase 0 receipt system for the app:

- a general-purpose receipt model
- append-only local persistence
- explicit caller-provided correlation IDs for multi-step flows
- JSON export as one array payload
- full local receipt reset support

This strategy is intentionally scoped to what can be implemented now without inventing the full module-boundary enforcement promised by `P0-701`.

## Locked Decisions

These decisions are already provided and should not be re-opened during implementation:

- receipt scope is broad across the app, not account-only
- storage is a SwiftData-backed model
- correlation IDs are explicit and caller-provided only
- export format is a single JSON array
- receipt reset is included in `P0-501`
- redaction in this ticket covers only:
  - raw RPC URLs
  - raw error strings

## Current State

The repo already has one useful seam:

- [`Auralis/Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift) exists as the placeholder event-recording boundary created during `P0-201`

What does not exist yet:

- no shared receipt model
- no append-only receipt store
- no export path
- no reset path for receipts
- no common correlation-ID discipline across services

The important nuance is that `P0-201` deliberately avoided hard-coupling account flows to a real receipt implementation. That was the correct move. `P0-501` should now plug into those seams instead of forcing a second round of account-flow rewrites.

## Constraints

- `P0-701` is not complete, so compile-time layered enforcement does not exist yet
- `P0-803` depends on `P0-501`, but this ticket only needs the redaction rules already confirmed for Phase 0
- the current app is still a single target, so any boundary here must be enforced by code shape and injection, not by target/module visibility
- receipts must be append-only through the public API, except for explicit full reset

## Strategy

### 1. Build a narrow receipt seam, not a logging empire

The ticket can proceed before `P0-701` if the code stays disciplined.

Implementation rule:

- introduce a small receipt-writing interface
- inject that interface into services or seams that need it
- do not let UI views know about SwiftData receipt persistence details
- do not build a global static logger

Why:

- `P0-701` explicitly wants Context and Services between UI and lower layers
- a narrow seam keeps `P0-501` useful now without pretending boundary enforcement already exists

### 2. Model receipts as immutable event records

Each receipt should be treated as a historical fact, not a mutable document.

Minimum fields needed to satisfy the ticket:

- stable receipt identifier
- monotonic sequence identifier for stable ordering fallback
- created-at timestamp
- event kind
- event category or domain
- correlation ID, optional on the model but caller-provided when a flow requires it
- sanitized payload data suitable for export

Append-only means:

- create only
- read/list only
- export only
- full reset only
- no update API
- no single-row delete API

Why:

- the ticket explicitly requires append-only storage
- sequence ID solves the clock-change ordering problem
- immutable receipts avoid “edit history” ambiguity

### 3. Keep payloads structured, but sanitize before persistence

Receipt payloads should be persisted only after they have gone through a sanitization pass.

For this ticket, sanitization must cover:

- raw RPC URLs
- raw error strings

That does not require a giant privacy framework yet. It does require one obvious function or type responsible for:

- accepting raw payload input
- redacting forbidden fields
- returning export-safe persisted payload data

Why:

- `P0-803` will build on this
- if sanitization is scattered through callers, someone will eventually forget it in the hottest error path

### 4. Make correlation IDs explicit at orchestration boundaries

Correlation IDs must be caller-provided only.

That means:

- top-level orchestration code creates the correlation ID
- downstream steps receive it and pass it into receipt recording explicitly
- the store never invents one automatically

Good fit examples in this repo:

- refresh flow entry points in [`Auralis/Auralis/Networking/NFTService.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTService.swift)
- lower-level fetch work in [`Auralis/Auralis/Networking/NFTFetcher.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTFetcher.swift)
- account flow seams already introduced through [`Auralis/Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift)

Why:

- this matches the product decision already made for `P0-501`
- caller ownership makes multi-step flow grouping explicit instead of magical

### 5. Separate receipt storage concerns from product-specific recorder facades

The store should not know what “account selected” means in product terms.

Recommended split:

- a generic receipt store owns persistence, ordering, export, and reset
- thin facades such as an account event recorder translate product events into receipt writes

Why:

- `P0-201` already created the account seam
- this keeps receipt persistence reusable for later flows without making the store full of feature-specific enums too early

### 6. Design reads for bounded access now

The ticket calls out store growth as an edge case. That means read APIs should be bounded from the start.

Recommended read shapes:

- fetch latest receipts with a limit
- fetch receipts for export as a dedicated bulk path
- fetch by correlation ID with a limit and stable ordering

Do not start with “return every receipt in normal app flows” just because the dataset is small today.

Why:

- export is the one place that legitimately wants the whole dataset
- UI or debugging tools should not normalize unbounded reads into everyday code

### 7. Implement reset as an explicit destructive operation

Reset is in scope now, but it should be deliberately shaped.

Rules:

- receipt reset is an explicit full wipe of the receipt store
- reset is separate from normal append-only APIs
- reset should not be smuggled in as a convenience delete helper

Why:

- it preserves the append-only contract
- it lines up with `P0-803` later, where wider local-data reset will matter across accounts, caches, and receipts

## What Can Ship Before P0-701

The following work is safe to implement now:

- SwiftData receipt model
- append-only receipt store
- monotonic sequence IDs
- payload sanitization for raw RPC URLs and raw errors
- JSON array export
- full receipt reset
- product-facing recorder seams that depend on an injected receipt-writing protocol
- initial integration in existing seams such as account event recording
- initial flow integration in orchestrators that already act like service boundaries

## What Still Requires P0-701

`P0-701` is still needed for the stronger version of this architecture.

Do not claim these are solved by `P0-501` alone:

- compile-time enforcement that UI cannot import or call Providers directly
- real module or target separation across UI, Context, Providers, Policy, Receipts, and Storage
- a repo-wide standardized logger interface agreed across all layers
- strict prevention of helper utilities leaking across boundaries
- guaranteed acyclic dependency rules between Context and Receipts through module structure instead of discipline

`P0-501` can prepare for those outcomes, but it cannot enforce them in a single-target app by itself.

## Proposed Implementation Order

### Slice A: Schema and store contract

- define the receipt model
- define append-only store protocol
- define export and reset APIs
- define the sanitization boundary

Definition of done:

- one clear model exists
- one clear append-only interface exists
- no update/delete-per-receipt API exists

### Slice B: SwiftData-backed store

- implement persistence
- assign monotonic sequence IDs
- implement bounded reads
- implement export as one JSON array
- implement full reset

Definition of done:

- receipts persist across relaunch
- stable ordering works with timestamp ties or clock weirdness
- export emits valid JSON

### Slice C: Recorder facades

- implement a receipt-backed account event recorder behind the existing seam
- add one generic receipt recorder or writer adapter for future flows

Definition of done:

- `P0-201` account events can write real receipts without changing account-domain rules
- the generic store remains independent from account-specific event names

### Slice D: Correlated flow integration

- wire explicit correlation IDs through one real multi-step flow
- good candidate: refresh to fetch to context-building orchestration

Definition of done:

- multiple receipts from one flow share the same caller-owned correlation ID
- no layer below the caller fabricates IDs

### Slice E: Tests and hardening

- persistence tests
- append-only API tests
- ordering tests using sequence fallback
- sanitization tests
- export tests
- reset tests

Definition of done:

- the ticket test plan is covered in code
- redaction rules are executable, not aspirational

## Expected File Areas

Likely new files:

- a receipt model under `Auralis/Auralis/DataModels/`
- a receipt store and sanitization area under a new receipt-focused folder in `Auralis/Auralis/`
- receipt export helpers if needed
- receipt-store tests under `Auralis/AuralisTests/`

Likely modified files:

- [`Auralis/Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift)
- [`Auralis/Auralis/Accounts/AccountStore.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountStore.swift)
- [`Auralis/Auralis/Networking/NFTService.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTService.swift)
- [`Auralis/Auralis/Networking/NFTFetcher.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTFetcher.swift)
- [`Auralis/Auralis/AuralisApp.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/AuralisApp.swift) if the model container must include new receipt types

## Key Risks

- broad receipt scope can turn into an unbounded taxonomy exercise if event categories are over-designed too early
- if sequence IDs are generated casually, ordering bugs will hide behind timestamps until clocks drift or imports race
- if sanitization happens after persistence instead of before it, export safety will be built on wishful thinking
- if product code writes directly to SwiftData receipt models, `P0-701` will later have to unwind those shortcuts
- full reset is easy to add incorrectly if it shares code paths with normal store operations

## Decisions To Preserve Across Sessions

- `P0-501` is allowed to proceed before `P0-701`
- the safe pre-`P0-701` shape is a narrow injected seam, not a global logger
- use SwiftData for receipt persistence
- keep receipts append-only except for explicit full reset
- use caller-provided correlation IDs only
- export format is one JSON array
- sanitize raw RPC URLs and raw errors before persistence
- design bounded reads from the start
- do not claim module-boundary enforcement until `P0-701` actually exists

## Suggested Next Chat Prompt

“Implement Slice A for `P0-501` from `P0-501-Strategy.md`: define the receipt model, append-only store protocol, sanitization boundary, and tests for immutability-oriented API shape.”
