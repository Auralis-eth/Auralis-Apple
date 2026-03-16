# P0-201 Strategy: Watch-Only Accounts + Persistence

## Ticket

`P0-201` implements watch-only account support as a first-class app identity primitive:

- create account
- remove account
- list persisted accounts
- select active account
- persist state across relaunch

This strategy is written for handoff across chat sessions. It is intentionally grounded in the code that exists today.

## Current State

The repo is not starting from zero. Parts of the data model already exist, but the behavior is incomplete and spread across the UI shell.

What already exists:

- [`EOAccount`](Auralis/Auralis/DataModels/EOAccount.swift) is a SwiftData model with unique `address`, optional `name`, and `access`.
- `watch-only` is already modeled as `EthereumAddressAccess.readonly`.
- [`MainAuraView`](Auralis/Auralis/Aura/MainAuraView.swift) restores `currentAddress` from `@AppStorage`, resolves an account, and triggers NFT refresh when identity changes.
- [`AddressInputView`](Auralis/Auralis/Aura/Auth/AddressEntryView.swift) can create and persist an account from typed input.
- [`QRScannerView`](Auralis/Auralis/Aura/Auth/QRScannerView.swift) can create and persist an account from a scanned address.

What is still missing or unsafe:

- Account creation is duplicated in multiple views instead of going through one account service/store.
- Duplicate detection is not deterministic for case-insensitive address matches.
- Active-account selection is stored as a raw string, not as a managed account selection flow.
- Deleting the active account has no defined fallback behavior.
- `MainAuraShellLogic` creates transient fallback `EOAccount(address:)` values when persistence has not caught up, which muddies the line between persisted and in-memory identity.
- Logout currently deletes *all* `EOAccount` records from [`HomeTabView`](Auralis/Auralis/Aura/Home/HomeTabView.swift), which conflicts with the goal of keeping a local account roster.
- Receipt logging depends on `P0-501`, which is not complete yet.

What is intentionally still undecided:

- Account ordering has now been clarified for Phase 0:
  - primary: most recent activity / most recently selected first
  - secondary tie-break: insertion order / newest added first

## Constraints

- `P0-501` is not complete. We cannot block `P0-201` on it.
- The ticket graph has circular dependencies, so `P0-201` needs a staged implementation with a clean seam for receipt logging later.
- Changes should stay aligned with the existing shell architecture rather than bypassing `MainAuraView`.

## Strategy

### 1. Establish a single account domain seam

Introduce an account-focused store/service as the only place allowed to:

- normalize an address
- detect duplicates
- create a watch-only account
- remove an account
- resolve the active account
- choose fallback account after deletion

Suggested shape:

- `WatchAccountStore` or `AccountStore`
- injected with `ModelContext`
- instance-based, not `static`

Why:

- `AddressInputView` and `QRScannerView` currently write directly to SwiftData.
- The shell already has enough state orchestration work. It should react to identity changes, not own account CRUD rules.

### 2. Normalize account identity before persistence

Use one canonical address form for comparisons and storage. At minimum:

- trim whitespace
- extract embedded address if needed
- lowercase for uniqueness checks and lookups

Decision:

- Prefer storing the canonical lowercase address in `EOAccount.address`.
- If checksum display matters later, add a separate display field instead of mixing comparison and presentation concerns.

Why:

- The ticket explicitly requires case-insensitive duplicate handling.
- Current lookups in `MainAuraShellLogic` use exact string equality.

### 3. Separate persisted identity from shell transition logic

Refactor `MainAuraShellLogic` so it no longer invents transient `EOAccount` instances for addresses that are not yet persisted.

Target behavior:

- Shell restore should resolve only persisted accounts.
- Add/select flows should persist first, then update active selection.
- If persisted active address is missing or corrupt, the shell should choose a safe fallback:
  - first remaining account if one exists
  - otherwise onboarding

Why:

- Right now the shell can fabricate an account object that looks real but is not in the store.
- That makes duplicate handling, deletion, and migration recovery harder to reason about.

### 4. Keep active account as durable selection, not accidental side effect

Retain `@AppStorage("currentAccountAddress")` as the app-launch bootstrap key for now, but treat it as:

- active-account selection state
- not the source of truth for account existence

Rules:

- When selecting an account, update `currentAccountAddress`.
- When deleting the active account, compute fallback and then update `currentAccountAddress`.
- When no accounts remain, clear `currentAccountAddress` and route to onboarding.

This keeps the current launch path intact while making the selection behavior explicit.

### 5. Add account-management UI in small slices

Do not try to redesign the whole auth flow in one pass.

Recommended sequence:

1. Keep gateway add flow, but route creation through the new store.
2. Add an account list surface for persisted accounts.
3. Add select/remove actions from that list.
4. Update logout behavior so it clears the active session state without silently destroying the whole roster unless that is an intentional product decision.

Likely touch points:

- [`AddressEntryView`](Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
- [`QRScannerView`](Auralis/Auralis/Aura/Auth/QRScannerView.swift)
- [`GatewayView`](Auralis/Auralis/Aura/Auth/GatewayView.swift)
- [`ProfileCardView`](Auralis/Auralis/Aura/Home/ProfileCardView.swift) or another shell-adjacent surface for switching/removing accounts
- [`HomeTabView`](Auralis/Auralis/Aura/Home/HomeTabView.swift) for logout semantics

### 6. Stub receipt logging behind a protocol

Do not wait for `P0-501`.

Define a tiny interface now, for example:

- `AccountEventRecorder.record(.added(address))`
- `record(.removed(address))`
- `record(.selected(address))`

Phase 0 implementation:

- no-op recorder by default
- optional debug logger

When `P0-501` lands:

- plug the receipt-backed implementation into the same interface

This breaks the circular dependency cleanly.

### 7. Define duplicate resolution behavior explicitly

Duplicate detection must be case-insensitive, but duplicate handling should not be a vague "maybe merge" flow.

Phase 0 rule:

- detect duplicate account by canonical address comparison
- present the duplicate as an existing account
- allow the user to cancel, or overwrite metadata
- if the user chooses overwrite, delete the old record and recreate it rather than mutating in place

Why:

- this matches the current product direction
- it is conservative about data cleanliness
- it avoids hidden partial merges of nickname, flags, holdings, or other account metadata

### 8. Add recovery behavior for corrupt or mismatched storage

Needed because the ticket calls this out explicitly.

Minimum safe behavior:

- if active address points to no persisted account, clear or replace it deterministically
- if account fetch/save fails, show user-facing error and avoid half-selected state
- if SwiftData migration/storage is corrupted, provide a reset path that clears account selection and re-enters onboarding

This can start small. It does not need a full migration framework to satisfy Phase 0.

## Proposed Implementation Order

### Slice A: Data and orchestration

- Add `AccountStore` with create/remove/list/select helpers.
- Centralize address normalization and duplicate detection.
- Add event-recorder protocol with no-op default.

Definition of done for Slice A:

- No UI writes `EOAccount` directly.
- Case-insensitive duplicates are handled in one place.

### Slice B: Shell integration

- Update `MainAuraView` and `MainAuraShellLogic` to resolve only persisted accounts.
- Define fallback selection when active account disappears.
- Keep NFT refresh trigger behavior when active account changes.

Definition of done for Slice B:

- Active-account changes are deterministic.
- Deleting active account sends the app either to fallback account or onboarding.

### Slice C: UI account management

- Update gateway typed-entry and QR flows to use the store.
- Add account list/select/remove UI.
- Revisit logout behavior so it does not wipe persisted accounts unless explicitly intended.

Definition of done for Slice C:

- User can add, remove, list, and switch accounts from the app.
- Duplicate-add behavior is deterministic and user-visible.

### Slice D: Tests

- Add store-level tests for normalization, duplicates, selection, fallback, and deletion.
- Update shell tests for restore behavior and missing-active-account recovery.
- Add UI-level smoke coverage for add/select/delete if the current test harness makes that practical.

### Slice E: Ordering decision

Account ordering is now defined for Phase 0.

Implementation rule:

- sort accounts by most recent activity, using most recently selected as the primary signal
- if accounts are tied on activity, use insertion order with newest added first as the tie-break
- if the model does not yet contain the fields needed to support this, add them as part of the `EOAccount` in-place evolution for `P0-201`

## Expected File Areas

Likely new files:

- `Auralis/Auralis/Accounts/AccountStore.swift` or similar
- `Auralis/Auralis/Accounts/AccountEventRecorder.swift`
- `Auralis/AuralisTests/AccountStoreTests.swift`

Likely modified files:

- [`Auralis/Auralis/Aura/MainAuraView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraView.swift)
- [`Auralis/Auralis/Aura/MainAuraShell.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraShell.swift)
- [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
- [`Auralis/Auralis/Aura/Auth/QRScannerView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/QRScannerView.swift)
- [`Auralis/Auralis/Aura/Home/HomeTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/HomeTabView.swift)
- [`Auralis/Auralis/DataModels/EOAccount.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/DataModels/EOAccount.swift)

## Key Risks

- Lowercasing persisted addresses can create migration edge cases if existing rows contain mixed-case addresses.
- `@AppStorage` plus `@Query` plus local `@State` already form a three-way identity handshake in the shell. Changes there can cause launch-loop bugs if done casually.
- Deleting all accounts on logout is probably masking the lack of a real account-selection model today. Fixing `P0-201` likely means changing logout semantics.
- NFT refresh timing and deep-link replay both depend on active-account transitions staying coherent.
- Account ordering depends on metadata fields that may not exist yet, so the model change and sorting behavior need to be designed together.

## Decisions To Preserve Across Sessions

- Do not block `P0-201` on `P0-501`.
- Add an account event seam now and wire receipts later.
- Centralize account CRUD and normalization before expanding UI.
- Remove transient fake-account creation from shell logic.
- Treat persisted account roster and active selection as related but separate concerns.
- Keep address persistence behavior aligned with the current app unless a later ticket explicitly changes it.
- For duplicate overwrite, delete and recreate the account record rather than mutating the old one.
- Account ordering is: most recent activity / most recently selected first, then newest added first.

## Suggested Next Chat Prompt

“Implement Slice A for `P0-201` from `P0-201-Strategy.md`: create the account store/event-recorder seam, centralize watch-only account creation and duplicate detection, and add tests.”
