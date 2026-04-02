# P0-701B Tickets And Session Handoff

## Summary

Complete the layered-boundaries enforcement pass so shell/service/view ownership rules are no longer just conventions.

## Ticket Status

Partially blocked behind stable seam adoption, but targeted enforcement work is legitimate.

## Execution Checklist

### 1. Confirm the active bypasses

- [ ] Re-read `P0-701B-Strategy.md` and `P0-701B-Dependency-Note.md`.
- [ ] Confirm which current shortcut paths are the highest-value enforcement targets.
- [ ] Confirm which enforcement work would create too much churn right now.

### 2. Implement the first enforcement pass

- [ ] Remove or gate the clearest shell/service boundary bypasses.
- [ ] Tighten action and routing ownership where the seam is already real.
- [ ] Keep enforcement changes local and defensible.

### 3. Cover required edge cases

- [ ] Enforcement does not break active product flows.
- [ ] The stricter contract remains understandable to future contributors.
- [ ] Denied or redirected paths fail honestly.

### 4. Validate the vertical slice

- [ ] Verify the targeted bypasses are actually closed.
- [ ] Verify later smoke-test work has a clearer target surface.
- [ ] Record deferred broad enforcement separately.

## Critical Edge Case

Enforcement must close real boundary leaks without destabilizing active product flows.

## Validation

Close targeted bypass paths and make architecture ownership easier to verify in later smoke tests.

## Handoff Rule

If a proposed enforcement change requires broad restructuring, defer it rather than letting `P0-701B` become an unfocused cleanup marathon.
