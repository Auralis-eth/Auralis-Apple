# P0-452 Strategy: Music collection + item detail screens

## Status

Blocked

## Ticket

Build read-only music collection and item details with explorer links, copy actions, local pin or favorite actions, and provenance labels.

## Dependencies

P0-451, P0-502 slices, P0-702, with `P0-101D` as a recommended parallel foundation

## Strategy

- Wait on the underlying library and trust-labeling seams.
- Do not treat `P0-101D` as the primary blocker.
- Use `P0-101D` later to converge warning and empty-state presentation.

## Key Risk

Missing artwork, long metadata, and unavailable explorer links must degrade safely without implying trust.

## Definition Of Done

- Detail flows are readable and safe.
- Metadata trust treatment is explicit.
- Shared warning and empty-state presentation can later align with `P0-101D`.

## Validation Target

Navigate collection to item detail and back, log copy and explorer actions, and label metadata as untrusted where required.
