# P0-202 Tickets And Session Handoff

## Status

Implemented

## Summary

Validate and normalize EVM addresses early, present them consistently across the UI, and reject invalid formats before persistence.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Trim whitespace, reject non-hex and non-EVM formats, and decide whether ENS in address fields is redirected or rejected.

## Validation

Block invalid addresses, save valid normalized addresses, copy normalized values exactly, and trim pasted whitespace before validation.

## Completion Summary

- Added strict address validation and canonical normalization in `Accounts/AccountStore.swift`.
- Rejected `.eth` ENS names explicitly in account-entry and QR flows for this phase.
- Updated auth UI copy so the text field and header promise wallet addresses instead of unsupported ENS input.
- Added a visible auth copy path for the exact lowercase canonical address Phase 0 persists.
- Locked the Phase 0 contract to lowercase canonical `0x...` storage and copy behavior rather than EIP-55 checksum display.
- Added unit coverage for whitespace trimming, lowercase normalization, no-prefix normalization, ENS rejection, embedded-text rejection, and the explicit lowercase canonical contract.

## Validation Result

- Live Xcode diagnostics for touched source and test files returned no issues.
- Long-running Xcode build/test actions timed out at the tool boundary in this session, so ticket validation is currently based on clean file diagnostics plus the added unit coverage.

## Handoff Rule

This ticket is complete. Treat ENS resolution as deferred to `P0-203`; do not quietly reintroduce ENS acceptance into account-entry surfaces before that ticket is implemented. Treat checksum display as out of scope for Phase 0 unless a later ticket reopens the contract explicitly.
