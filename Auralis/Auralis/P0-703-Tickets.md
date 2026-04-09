# P0-703 Tickets And Session Handoff

## Summary

Add smoke-test coverage that proves key safety, policy, and boundary rules do not have obvious bypass paths.

## Ticket Status

Completed for the current first smoke-test slice.

## Execution Checklist

### 1. Confirm the first no-bypass targets

- [x] Re-read `P0-703-Strategy.md` and `P0-703-Dependency-Note.md`.
- [x] Confirm which rules are stable enough to smoke-test.
- [x] Confirm whether each target should be blocked, denied, or labeled.

### 2. Implement the first smoke tests

- [x] Add a small set of high-value smoke tests.
- [x] Target practical bypass scenarios rather than abstract coverage.
- [x] Keep the suite maintainable and understandable.

### 3. Cover required edge cases

- [x] Tests do not rely on unstable implementation details.
- [x] Failure output makes the bypass understandable.
- [x] The suite stays focused on real enforcement risk.

### 4. Validate the vertical slice

- [x] Verify representative bypass paths are blocked or labeled.
- [x] Verify the suite is stable enough to keep in regular validation.
- [x] Record later expansion separately.

## Critical Edge Case

Smoke tests must prove real safety rules without becoming brittle stand-ins for the whole app architecture.

## Validation

Prove representative bypass paths are blocked or labeled correctly through a small maintainable smoke suite.

## Implementation Notes

- Added a dedicated `NoBypassSmokeTests` suite rather than hiding the ticket inside unrelated feature tests.
- The first smoke slice covers:
  - blocked observe-mode action denial with receipt evidence
  - allowed observe-mode plugin behavior without false denial receipts
  - deep-link trust labeling only when raw external URL input is present
  - search-owned routing handing detail destinations back to their owning tabs
- This ticket intentionally does not try to smoke-test every view, link button, or provider-backed string in the app.

## Validation Notes

- `Auralis` build passed.
- 4 dedicated smoke tests passed in `NoBypassSmokeTests`.

## Handoff Rule

If the underlying rule is still moving, defer the smoke test rather than freezing unstable behavior into test code.
