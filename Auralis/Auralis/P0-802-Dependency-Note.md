# P0-802 Dependency Note

## Status

Partially blocked

## Dependency Read

- This ticket is most valuable after the major Phase 0 product slices are mounted.
- `P0-801` is canceled, so the baseline should measure normal live/cached/degraded behavior instead of waiting on a demo/offline product mode.
- Active shell, media, search, and receipt flows should be real enough to measure before deep tuning starts.

## Safe First Slice

- Identify representative baseline flows now.
- Use address-entry submit to usable shell and ERC-20 detail opening as the first measured flows.
- Defer heavy tuning until those flows are stable enough to measure honestly.
- Prefer concrete performance/stability observations over vague optimization work.
- Treat leak checking as part of the baseline, but do not let speculative or broad architectural cleanup block the ticket.

## Rule For Planning

Do not let `P0-802` become premature micro-optimization before the app slices settle.
