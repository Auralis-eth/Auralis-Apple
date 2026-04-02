# P0-452 Strategy: Music collection + item detail screens

## Status

Startable

## Ticket

Implement the first real music collection and item detail screens on top of the completed `P0-451` music library foundation.

## Dependencies

- `P0-451`
- `P0-101A`
- `P0-403` slice

## Strategy

- Build detail screens on the dedicated music library/index foundation rather than going back to raw ad hoc filtering.
- Reuse source `NFT` data where it remains the canonical metadata owner.
- Keep collection detail and item detail separate enough that later richer playback and curation features can attach cleanly.

## Key Risk

Avoid letting detail screens collapse back into raw `NFT`-driven view logic or absorb broader audio-engine work that belongs in later tickets.

## Definition Of Done

- Music item detail exists and is routable from the library.
- Music collection detail exists for grouped browsing.
- Both screens degrade honestly when metadata is partial.

## Validation Target

Open music item and collection detail from the mounted Music surface, preserve graceful partial-metadata handling, and leave room for later playback/capture deepening.
