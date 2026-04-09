# P0-702 Tickets And Session Handoff

## Summary

Label untrusted input clearly across the shell so users can distinguish system-known values from externally sourced values.

## Ticket Status

Completed for the current first trust-label slice.

## Execution Checklist

### 1. Confirm the trust-boundary contract

- [x] Re-read `P0-702-Strategy.md` and `P0-702-Dependency-Note.md`.
- [x] Confirm which surfaces expose untrusted input first.
- [x] Confirm the first label/copy/style contract.

### 2. Implement the labeling system

- [x] Add the first reusable untrusted-input labeling pattern.
- [x] Apply it to representative surfaces.
- [x] Keep trust signals visually and semantically consistent.

### 3. Cover required edge cases

- [x] Labels remain understandable on compact layouts.
- [x] Trusted and untrusted values are not visually conflated.
- [x] Labeling does not accidentally imply data is verified when it is not.

### 4. Validate the vertical slice

- [x] Verify representative untrusted values are clearly labeled.
- [x] Verify the labels are understandable without internal jargon.
- [x] Record broader rollout work outside this ticket.

## Critical Edge Case

Trust labeling must be clear enough to matter, but not so noisy that users ignore it everywhere.

## Validation

Render representative untrusted values with a consistent labeling contract and preserve understandable trust boundaries.

## Implementation Notes

- Added a reusable `AuraTrustLabel` primitive with specific trust-forward variants: `Untrusted metadata`, `Untrusted link`, `Untrusted scan`, and `Untrusted deep link`.
- Applied the first slice to representative mounted surfaces:
  - search local-match metadata
  - shared NFT detail metadata
  - NFT collection detail metadata
  - external OpenSea and explorer links
  - QR scan entry surface
  - ENS mapping-change alert copy
  - deep-link route error screen
- This ticket intentionally stops short of labeling every provider-origin field in the app.

## Validation Notes

- `Auralis` build passed.
- 10 focused non-UI tests passed, including the new trust-label contract tests and existing deep-link/search route coverage.

## Handoff Rule

If the work starts turning into full search-safety behavior, move the extra scope into the relevant search or enforcement tickets.
