# P0-451 Strategy: Music library index + storage (v0)

## Status

Complete

## Ticket

Implement a minimal music library index with local persistence and refresh receipts, deriving the first index from the existing SwiftData-backed local `NFT` store for Phase 0.

## Dependencies

- `P0-101A`
- `P0-101E`
- `P0-501`
- `P0-502` slices

## Strategy

- Start from the existing SwiftData-backed local `NFT` store and derive a dedicated music library index from locally persisted records where `nft.isMusic()` is true.
- Treat this as the dedicated Music foundation phase, not just pre-work.
- Keep the initial index useful to Home and Search even before the full context stack is complete.
- Layer deeper integration later rather than holding the whole ticket.
- Reuse the existing receipt-store pattern for refresh/index activity instead of inventing a parallel logging path.

## Key Risk

Support empty datasets, duplicate items, and partial or malformed local NFT metadata without crashing or losing a usable shell.
Avoid shaping the first persistence model so narrowly that later collection/detail surfaces need a second storage rewrite.

## Definition Of Done

- The music index is real and locally usable.
- Home and Search can consume it before every later library surface is complete.
- Later context integration can attach cleanly.
- The first slice leaves a clean seam for `P0-452` instead of forcing collection/detail assumptions into `P0-451`.

## Validation Target

Load the library, persist local state across relaunch if needed, and emit receipts on refresh.
