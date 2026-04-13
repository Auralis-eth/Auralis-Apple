# P0-801 Strategy: Deterministic demo dataset + offline mode behavior

## Status

Startable

## Ticket

Define the deterministic demo dataset and offline mode behavior for Phase 0 so the app remains coherent when live data is absent or intentionally replaced.

## Dependencies

- `P0-101D`
- active shell/data surfaces that the demo/offline slice will exercise

## Strategy

- Use bundled fixed JSON as the canonical deterministic demo dataset.
- Launch demo mode from the address-entry surface in non-production builds only.
- Cover Home, Newsfeed, NFT Tokens, ERC-20 Tokens, Music, Receipts, and Gas in demo mode.
- Keep demo data clearly separate from live and cached real data.
- Treat offline mode as a post-entry product behavior, not just a network failure side effect.
- For real accounts, show cached real data first and never substitute demo data.
- Make the shell honest about what is demo, cached, stale, offline, or unavailable.

## Key Risk

Avoid mixing demo and live data so loosely that users or later code paths cannot tell which truth they are looking at.

## Definition Of Done

- A deterministic demo dataset contract exists.
- Demo mode entry and non-production gating are defined.
- Offline mode behavior is defined and usable.
- The shell communicates data provenance honestly.

## Validation Target

Run the app in deterministic demo/offline conditions and preserve understandable provenance and fallback behavior.
