# P0-802 Strategy: Performance + stability baseline

## Status

Partially blocked

## Ticket

Establish the Phase 0 performance and stability baseline once the core product slices are far enough along to measure meaningfully.

## Dependencies

- major Phase 0 product slices in place
- active shell/data/media surfaces

## Strategy

- Measure and harden the app based on real mounted flows.
- Use `valid address submit -> first usable main shell` and `open ERC-20 screen` as the first baseline flows.
- Capture timings, user-visible latencies, and leak/stability findings for those flows.
- Fix high-confidence leaks in the measured flows and defer broader cleanup explicitly.
- Focus on the highest-value bottlenecks and crash/regression risks first.
- Keep the baseline concrete enough that later work can detect regressions.

## Key Risk

Avoid premature tuning before the important product flows are stable enough to measure honestly.

## Definition Of Done

- The app has a meaningful Phase 0 performance/stability baseline.
- High-value regressions are identified and addressed for the measured flows.
- Later work has a clearer reference point.

## Validation Target

Measure representative shell, data, and media flows and document the accepted performance/stability baseline.
