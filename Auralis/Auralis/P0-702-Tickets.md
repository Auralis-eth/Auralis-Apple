# P0-702 Tickets And Session Handoff

## Summary

Label untrusted input clearly across the shell so users can distinguish system-known values from externally sourced values.

## Ticket Status

Startable.

## Execution Checklist

### 1. Confirm the trust-boundary contract

- [ ] Re-read `P0-702-Strategy.md` and `P0-702-Dependency-Note.md`.
- [ ] Confirm which surfaces expose untrusted input first.
- [ ] Confirm the first label/copy/style contract.

### 2. Implement the labeling system

- [ ] Add the first reusable untrusted-input labeling pattern.
- [ ] Apply it to representative surfaces.
- [ ] Keep trust signals visually and semantically consistent.

### 3. Cover required edge cases

- [ ] Labels remain understandable on compact layouts.
- [ ] Trusted and untrusted values are not visually conflated.
- [ ] Labeling does not accidentally imply data is verified when it is not.

### 4. Validate the vertical slice

- [ ] Verify representative untrusted values are clearly labeled.
- [ ] Verify the labels are understandable without internal jargon.
- [ ] Record broader rollout work outside this ticket.

## Critical Edge Case

Trust labeling must be clear enough to matter, but not so noisy that users ignore it everywhere.

## Validation

Render representative untrusted values with a consistent labeling contract and preserve understandable trust boundaries.

## Handoff Rule

If the work starts turning into full search-safety behavior, move the extra scope into the relevant search or enforcement tickets.
