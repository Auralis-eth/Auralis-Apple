# P0-452 Dependency Note

## Status

Startable

## Dependency Read

- `P0-451` is complete enough to provide the library/index foundation for this ticket.
- `P0-101A` already gives the shell and routing baseline needed for detail presentation.
- `P0-403` can support provenance or receipt-aware detail affordances where useful, but it does not need to block the first detail screens.

## Safe First Slice

- Build item detail first, then collection detail if the shared contract stays clean.
- Use the current music index plus source `NFT` metadata instead of inventing a second music-detail data model prematurely.
- Keep playback and deeper curation work out of scope unless it is required for basic screen correctness.

## Rule For Planning

Do not turn `P0-452` into the broader Audio Engine buildout or into playlist-management work.
