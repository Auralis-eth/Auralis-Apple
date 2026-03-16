# P0-201 Tickets And Session Handoff

This document converts the strategy in [`P0-201-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-201-Strategy.md) into execution-oriented steps that can be handed from session to session.

## Scope

`P0-201` implements watch-only account support with local persistence:

- create account
- remove account
- list persisted accounts
- select active account
- persist account state across relaunch

Phase 0 decisions already locked:

- evolve `EOAccount` in place
- keep new metadata fields minimal
- nickname/display name is in scope
- metadata also includes minimal timestamps, source/flags, and very basic holdings
- duplicate detection is case-insensitive
- duplicate overwrite means delete-and-recreate
- logout is separate from account deletion
- account management must be available from an in-app switcher
- account ordering is `lastSelectedAt` descending, then newest-added first
- receipt logging is behind a no-op seam until `P0-501` is ready

## Step Plan

### Step 1: Lock model and domain decisions

- Finalize the minimal `EOAccount` Phase 0 field set.
- Keep address persistence behavior aligned with the current app.
- Treat "most recent activity" as `lastSelectedAt`.

Status:

- completed in code
- `EOAccount` now carries the locked Phase 0 metadata set:
  - `address`
  - `name`
  - `access`
  - `source`
  - `addedAt`
  - `lastSelectedAt`
  - `trackedNFTCount`
- address storage behavior was intentionally left unchanged in this step
- ordering can now use `lastSelectedAt ?? addedAt`, with `lastSelectedAt` as the primary activity signal

### Step 2: Add account domain seam

- Create `AccountStore` and account event recording seam.
- Centralize create/remove/list/select logic.
- Centralize duplicate detection and duplicate overwrite handling.

Status:

- completed in code
- added `AccountStore` as the SwiftData-backed seam for:
  - address normalization
  - list ordering
  - create/select/remove operations
  - case-insensitive duplicate detection
  - delete-and-recreate overwrite behavior
  - active-account deletion fallback calculation
- added `AccountEventRecorder` with a no-op default implementation for the future `P0-501` receipt seam

### Step 3: Add tests for the store seam

- Add tests for create/remove/select/list behavior.
- Add tests for duplicate detection and delete-and-recreate overwrite behavior.
- Add tests for ordering using `lastSelectedAt` then newest-added.

Status:

- completed in code
- expanded `AccountStoreTests` to cover:
  - canonical lookup for raw, embedded, and invalid address inputs
  - invalid create/select/remove error paths
  - inactive-account deletion without fallback selection
  - ordering guarantees for `lastSelectedAt` first, then newest-added
- existing duplicate overwrite, selection, fallback removal, and list-order tests remain in place and now form the full Step 3 seam coverage set

### Step 4: Integrate shell identity flow

- Update shell logic to resolve persisted accounts only.
- Remove transient fallback `EOAccount(address:)` behavior.
- Preserve app bootstrapping via `currentAccountAddress`, but treat it as active selection state.

Status:

- completed in code
- `MainAuraShellLogic` now resolves persisted accounts only and no longer fabricates transient `EOAccount(address:)` values
- cold-start restore now:
  - keeps the saved selection when it resolves to a persisted account
  - falls back to the preferred persisted account when the saved address is stale
  - clears the saved address when no persisted accounts remain
- runtime `currentAddress` changes now keep selection intent in `currentAccountAddress` while resolving `currentAccount` only from persisted accounts
- `MainAuraView` now applies the restore result’s resolved selection state during startup

### Step 5: Wire gateway and QR entry through the store

- Update typed-entry flow to stop inserting `EOAccount` directly.
- Update QR flow to stop inserting `EOAccount` directly.
- Route duplicate handling through one deterministic path.

### Step 6: Add in-app account management UI

- Add account list surface.
- Add select/remove actions.
- On deleting the active account with other accounts remaining, show the account selection screen.

### Step 7: Separate logout from deletion

- Update logout to clear active selection and cached NFT data.
- Do not wipe all persisted accounts on logout.

### Step 8: Validate end-to-end behavior

- add address
- remove address
- switch active account
- duplicate add flow
- delete active account flow
- relaunch persistence

## What already changed:

- [`P0-201-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-201-Strategy.md) was created and refined into a durable implementation strategy.
- Product and architecture decisions that were previously ambiguous are now documented:
  - duplicate overwrite is delete-and-recreate
  - active-account ordering is `lastSelectedAt` descending, then newest-added first
  - `EOAccount` evolves in place
  - logout and account deletion are separate operations
  - `P0-201` is not blocked on `P0-501`
- Steps 1 through 4 are now implemented in code:
  - `EOAccount` carries the locked Phase 0 metadata
  - `AccountStore` and `AccountEventRecorder` centralize the account seam
  - `AccountStoreTests` now cover create/remove/select/list, duplicate overwrite, lookup normalization, error paths, and ordering rules
  - shell restore/account-change logic now resolves persisted accounts without fake fallback models

## Files touched through Step 4:

Planning artifacts:

- [`P0-201-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-201-Strategy.md)
- [`P0-201-Tickets.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-201-Tickets.md)
- [`Journal.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Journal.md)

Implemented app and test files so far:

- [`Auralis/Auralis/DataModels/EOAccount.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/DataModels/EOAccount.swift)
- [`Auralis/Auralis/Accounts/AccountStore.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountStore.swift)
- [`Auralis/Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift)
- [`Auralis/Auralis/Aura/MainAuraShell.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraShell.swift)
- [`Auralis/Auralis/Aura/MainAuraView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraView.swift)
- [`Auralis/AuralisTests/EOAccountTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/EOAccountTests.swift)
- [`Auralis/AuralisTests/AccountStoreTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/AccountStoreTests.swift)
- [`Auralis/AuralisTests/MainAuraShellLogicTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/MainAuraShellLogicTests.swift)

## Validation already done:

- Strategy review completed against the current shell/account code.
- Scope decisions for `P0-201` are documented and no longer waiting on open product questions.
- `AccountStore.swift` diagnostics: clean
- `AccountEventRecorder.swift` diagnostics: clean
- `AccountStoreTests` targeted run: 8 passed, 0 failed
- `EOAccount.swift` diagnostics: clean
- `MainAuraShell.swift` diagnostics: clean
- `MainAuraView.swift` diagnostics: clean
- `MainAuraShellLogicTests` targeted run: 10 passed, 0 failed
- full project build: succeeded
- `AccountStoreTests.swift` and `MainAuraShellLogicTests.swift` editor diagnostics currently show a duplicate Xcode Testing macro plugin-path conflict from two installed Xcode app paths; the actual test runs and project build both pass

## Next Session Handoff

If a new session picks this up, start with Step 5.

Steps 1 through 4 are complete in code. The next working session should wire typed entry and QR flows through `AccountStore` so account creation stops bypassing the seam.

Do not touch yet:

- advanced holdings derivation beyond the minimal Phase 0 metadata
- receipt-backed event persistence for `P0-501`
- broader account analytics/history features
- non-essential migration/recovery UX beyond the Phase 0 safe path
- any redesign of unrelated tab navigation or NFT refresh behavior

Read first:

- [`Auralis/Auralis/DataModels/EOAccount.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/DataModels/EOAccount.swift)
- `Auralis/Auralis/Accounts/AccountStore.swift`
- `Auralis/Auralis/Accounts/AccountEventRecorder.swift`
- `Auralis/AuralisTests/EOAccountTests.swift`
- `Auralis/AuralisTests/AccountStoreTests.swift`
- [`Auralis/Auralis/Aura/MainAuraShell.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraShell.swift)
- [`Auralis/Auralis/Aura/MainAuraView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraView.swift)
- [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
- [`Auralis/Auralis/Aura/Auth/QRScannerView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/QRScannerView.swift)
- [`Auralis/AuralisTests/MainAuraShellLogicTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/MainAuraShellLogicTests.swift)

Then implement:

- typed-entry flow that creates/selects accounts through `AccountStore`
- QR flow that creates/selects accounts through `AccountStore`
- duplicate handling that routes through one deterministic store path instead of ad hoc SwiftData inserts

Then validate in this order:

- file diagnostics for `AccountStore.swift`
- file diagnostics for `AccountEventRecorder.swift`
- file diagnostics for [`AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
- file diagnostics for [`QRScannerView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/QRScannerView.swift)
- targeted tests for `AccountStoreTests`
- targeted tests for [`MainAuraShellLogicTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/MainAuraShellLogicTests.swift)
- full project build

## Execution Rule

For every remaining step:

- implement the change
- add or update tests
- run Xcode diagnostics
- run targeted tests
- run a full build
- only then continue
