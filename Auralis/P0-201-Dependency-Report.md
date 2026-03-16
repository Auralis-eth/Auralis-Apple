# P0-201 Downstream Dependency Report

This document replaces the old task-by-task execution log for `P0-201`.

`P0-201` is complete in code. This file is now a dependency-facing report for later tickets that build on top of watch-only account support.

## Ticket Outcome

`P0-201` delivered the Phase 0 watch-only account foundation:

- create account
- remove account
- list persisted accounts
- select active account
- persist account state across relaunch

## What Downstream Tickets Can Rely On

The following behaviors are now treated as stable Phase 0 contracts:

- `EOAccount` is the persisted watch-only identity model
- account ordering is `lastSelectedAt` descending, then `addedAt` descending
- duplicate detection is case-insensitive
- duplicate add behavior is deterministic:
  - new account creates then selects
  - existing account reuses the persisted account and selects it
- duplicate overwrite policy remains delete-and-recreate
- shell restore resolves persisted accounts only
- the app no longer fabricates transient fallback `EOAccount(address:)` identities in shell logic
- deleting the active account computes a fallback account when one exists, otherwise returns to onboarding
- logout clears session state but does not delete the saved account roster
- account CRUD and selection rules live behind `AccountStore`
- account event logging already has an injectable seam through `AccountEventRecorder`

## Main Seams For Dependent Tickets

These are the primary integration points other tickets should use instead of reintroducing direct view-level logic:

- [`Auralis/Auralis/Accounts/AccountStore.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountStore.swift)
- [`Auralis/Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift)
- [`Auralis/Auralis/DataModels/EOAccount.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/DataModels/EOAccount.swift)
- [`Auralis/Auralis/Aura/MainAuraShell.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraShell.swift)
- [`Auralis/Auralis/Aura/MainAuraView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraView.swift)

## UI Surfaces Already Wired To The Account Seam

Later tickets should assume these surfaces already go through the account domain seam:

- [`Auralis/Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
- [`Auralis/Auralis/Aura/Auth/QRScannerView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/QRScannerView.swift)
- [`Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift)
- [`Auralis/Auralis/Aura/Home/HomeTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/HomeTabView.swift)
- [`Auralis/Auralis/Aura/Home/ProfileCardView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/ProfileCardView.swift)

## Specifically Relevant To P0-501

`P0-501` should build on these facts rather than reopening `P0-201`:

- `AccountEventRecorder` already exists as the seam for receipt-backed account events
- account add, remove, and select flows are already centralized enough to emit receipts from one place
- `P0-201` intentionally shipped with a no-op event recorder so receipt persistence can plug in later
- `P0-501` should integrate at the recorder seam, not by teaching views or unrelated shell code about receipt persistence

## Validation Status

The `P0-201` foundation has already been validated in code:

- `AccountStoreTests` cover create, remove, select, ordering, normalization, duplicate handling, and fallback behavior
- `MainAuraShellLogicTests` cover persisted-account restore behavior
- `HomeTabLogicTests` lock in logout-with-roster-preserved behavior
- `P0201FlowValidationTests` exercise the integrated add, switch, duplicate, remove, fallback, relaunch, and logout flows
- the consolidated `P0-201` validation run passed
- full project build succeeded

## Known Deferred Or Out-Of-Scope Areas

Dependent tickets should not assume these are solved by `P0-201`:

- receipt-backed persistence of account events
- broader account analytics/history
- advanced holdings derivation beyond the minimal Phase 0 metadata
- full storage-corruption recovery UX
- broader privacy/security controls beyond what later tickets add
- compile-time architectural boundary enforcement from `P0-701`

## Recommended Read Order For Dependent Tickets

1. [`P0-201-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-201-Strategy.md)
2. [`Auralis/Auralis/DataModels/EOAccount.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/DataModels/EOAccount.swift)
3. [`Auralis/Auralis/Accounts/AccountStore.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountStore.swift)
4. [`Auralis/Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift)
5. [`Auralis/Auralis/Aura/MainAuraShell.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraShell.swift)
6. [`Auralis/AuralisTests/AccountStoreTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/AccountStoreTests.swift)
7. [`Auralis/AuralisTests/MainAuraShellLogicTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/MainAuraShellLogicTests.swift)
8. [`Auralis/AuralisTests/P0201FlowValidationTests.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/AuralisTests/P0201FlowValidationTests.swift)

## Rule For Future Tickets

If a later ticket depends on `P0-201`, it should extend the existing account seam and shell restore rules rather than:

- inserting `EOAccount` directly from views
- reintroducing duplicate account logic in UI code
- restoring active identity from raw strings without persisted-account resolution
- treating logout as account deletion
