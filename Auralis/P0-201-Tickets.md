# P0-201 Tickets And Session Handoff

## Summary

Deliver watch-only account creation, removal, selection, roster persistence, and deterministic active-account restore through one account-domain seam.

## Ticket Status

Completed for the current Phase 0 account foundation.

## Execution Checklist

### 1. Establish the account seam

- [x] Centralize account CRUD and selection behind `AccountStore`.
- [x] Keep account event recording behind `AccountEventRecorder`.
- [x] Normalize and compare addresses canonically.

### 2. Integrate the shell and auth flows

- [x] Route typed entry and QR entry through the account seam.
- [x] Restore only persisted accounts at shell launch.
- [x] Keep active-account selection explicit through persisted selection state.

### 3. Cover required edge cases

- [x] Duplicate detection is case-insensitive and deterministic.
- [x] Deleting the active account computes a fallback when one exists.
- [x] Logout clears session state without deleting the saved account roster.

### 4. Validate the vertical slice

- [x] Verify add, switch, duplicate, remove, fallback, relaunch, and logout flows.
- [x] Verify ordering remains `lastSelectedAt` then `addedAt`.
- [x] Verify later tickets can extend the account seam instead of reintroducing direct view-level CRUD.

## Implementation Notes

- The stable account-domain seam is `Auralis/Auralis/Accounts/AccountStore.swift`.
- Account identity is persisted via `Auralis/Auralis/DataModels/EOAccount.swift`.
- Shell restore and active-account ownership live through `Auralis/Auralis/Aura/MainAuraShell.swift` and `Auralis/Auralis/Aura/MainAuraView.swift`.
- Gateway entry, QR scan, and account switching already route through the account seam.

## Validation Notes

- `AuralisTests/AccountStoreTests.swift` covers normalization, duplicates, selection, removal, ordering, and fallback behavior.
- `AuralisTests/MainAuraShellLogicTests.swift` covers persisted-account restore behavior.
- `AuralisTests/HomeTabLogicTests.swift` locks the logout-with-roster-preserved contract.
- `AuralisTests/P0201FlowValidationTests.swift` covers integrated add, switch, duplicate, remove, fallback, relaunch, and logout flows.
- The dependency report records a consolidated `P0-201` validation run plus a successful full project build.

## Critical Edge Case

The shell must never fabricate transient account identity that looks persisted when it is not.

## Handoff Rule

If a later ticket touches account behavior, extend `AccountStore` or `AccountEventRecorder` instead of inserting `EOAccount` directly from views.
