# P0-801 Strategy: Deterministic demo dataset + offline mode behavior

## Status

Startable

## Ticket

Define the deterministic demo dataset and offline mode behavior for Phase 0 so the app remains coherent when live data is absent or intentionally replaced.

## Dependencies

- `P0-101D`
- `P0-801` should align with active shell/data surfaces

## Strategy

- Keep demo data deterministic and clearly separate from live data.
- Treat offline mode as a product behavior, not just a network failure side effect.
- Make the shell honest about what is demo, cached, stale, or unavailable.

## Key Risk

Avoid mixing demo and live data so loosely that users or later code paths cannot tell which truth they are looking at.

## Definition Of Done

- A deterministic demo dataset contract exists.
- Offline mode behavior is defined and usable.
- The shell communicates data provenance honestly.

## Validation Target

Run the app in deterministic demo/offline conditions and preserve understandable provenance and fallback behavior.
