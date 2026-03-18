# P0-801 Strategy: Deterministic demo dataset + offline mode behavior

## Status

Blocked

## Ticket

Provide a deterministic demo dataset and safe offline behavior so the app remains demoable and usable without network connectivity.

## Dependencies

P0-451, P0-302, P0-303, with `P0-101D` as a recommended parallel foundation

## Strategy

- Start from deterministic data and degraded-mode semantics.
- Use `P0-101D` later to unify the final presentation of demo, stale, and empty states.
- Keep demo-mode clarity as a product rule, not just a visual styling problem.

## Key Risk

Users must not confuse demo content with real content, especially on first-run offline flows.

## Definition Of Done

- Demo content is deterministic and clearly labeled.
- Offline behavior is safe and usable.
- Final visual language can align with `P0-101D`.

## Validation Target

Use airplane mode on fresh install and after cache exists, and verify the demo dataset behaves consistently across relaunches.
