# P0-802 Tickets And Session Handoff

## Summary

Establish the Phase 0 performance and stability baseline once the core product slices are real enough to measure.

## Ticket Status

Partially blocked until the representative mounted flows are settled enough to benchmark honestly.

## Execution Checklist

### 1. Confirm the baseline flows

- [ ] Re-read `P0-802-Strategy.md` and `P0-802-Dependency-Note.md`.
- [ ] Use `valid address submit -> first usable main shell` as a baseline flow.
- [ ] Use `open ERC-20 screen` as a baseline flow.
- [ ] Confirm which conditions should be excluded until later.

### 2. Measure the baseline

- [ ] Capture representative timing and latency observations for the selected flows.
- [ ] Identify the highest-value stability risks.
- [ ] Run leak checks on the selected flows.
- [ ] Keep the baseline concrete and reproducible.

### 3. Cover required edge cases

- [ ] Offline/demo conditions are included only where the product path is real enough.
- [ ] Measurements are not dominated by obviously unstable placeholder work.
- [ ] Stability findings are separated from optional polish work.
- [ ] High-confidence leaks in measured flows are fixed here; broader cleanup is written as follow-on work.

### 4. Validate the vertical slice

- [ ] Verify the chosen flows are measurable and representative.
- [ ] Verify the resulting baseline is specific enough for future regressions.
- [ ] Record follow-on tuning outside this ticket.

## Critical Edge Case

The baseline must reflect real mounted product behavior, not placeholder-heavy or unstable intermediate states.

## Validation

Measure representative mounted flows and document a concrete Phase 0 performance/stability baseline.

## Handoff Rule

If the app slices are still moving too quickly to measure honestly, document the target baseline set and defer deeper tuning.
