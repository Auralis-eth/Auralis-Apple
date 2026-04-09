# P0-701B Tickets And Session Handoff

## Summary

Complete the layered-boundaries enforcement pass so shell/service/view ownership rules are no longer just conventions.

## Ticket Status

Completed for the current first enforcement slice.

## Execution Checklist

### 1. Confirm the active bypasses

- [x] Re-read `P0-701B-Strategy.md` and `P0-701B-Dependency-Note.md`.
- [x] Confirm which current shortcut paths are the highest-value enforcement targets.
- [x] Confirm which enforcement work would create too much churn right now.

### 2. Implement the first enforcement pass

- [x] Remove or gate the clearest shell/service boundary bypasses.
- [x] Tighten action and routing ownership where the seam is already real.
- [x] Keep enforcement changes local and defensible.

### 3. Cover required edge cases

- [x] Enforcement does not break active product flows.
- [x] The stricter contract remains understandable to future contributors.
- [x] Denied or redirected paths fail honestly.

### 4. Validate the vertical slice

- [x] Verify the targeted bypasses are actually closed.
- [x] Verify later smoke-test work has a clearer target surface.
- [x] Record deferred broad enforcement separately.

## Critical Edge Case

Enforcement must close real boundary leaks without destabilizing active product flows.

## Validation

Close targeted bypass paths and make architecture ownership easier to verify in later smoke tests.

## Implementation Notes

- `ShellServiceHub` is now the mounted owner for the shell-facing account-store, receipt-logger, search-history, and token-holdings seams.
- Auth/account-switching flows no longer construct `AccountStore` directly inside views.
- Search no longer creates its own `SearchHistoryStore` inline.
- Shell refresh/app-launch and ERC-20 native-balance sync no longer name lower-layer persistence/logging types directly at the call site.
- Broader component-level cleanup such as every direct `ReceiptEventLogger` use in deeper leaf views is intentionally deferred so this ticket stays focused on the highest-value shell-facing ownership leaks.

## Validation Notes

- `Auralis` build passed.
- 6 focused tests passed across the new boundary-factory suite plus existing account, history, and native-holdings contracts.

## Handoff Rule

If a proposed enforcement change requires broad restructuring, defer it rather than letting `P0-701B` become an unfocused cleanup marathon.
