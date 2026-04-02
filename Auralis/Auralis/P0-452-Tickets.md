# P0-452 Tickets And Session Handoff

## Summary

Implement the first music collection and item detail screens on top of the `P0-451` library/index foundation.

## Ticket Status

Startable.

## Execution Checklist

### 1. Confirm detail routing and data inputs

- [ ] Re-read `P0-452-Strategy.md` and `P0-452-Dependency-Note.md`.
- [ ] Confirm how Music library rows route into item detail.
- [ ] Confirm which source `NFT` and library-index fields belong on item vs collection detail.

### 2. Implement item detail

- [ ] Add the first music item detail screen.
- [ ] Show the essential track, collection, and artwork metadata.
- [ ] Keep the screen honest when playback or metadata is partial.

### 3. Implement collection detail

- [ ] Add the first grouped collection detail screen.
- [ ] Reuse the established routing and library contracts.
- [ ] Keep the collection screen distinct from full playlist or curation work.

### 4. Validate the vertical slice

- [ ] Verify detail screens open from the mounted Music surface.
- [ ] Verify partial metadata does not break item or collection detail.
- [ ] Record any deeper playback/capture work outside this ticket.

## Critical Edge Case

Music detail screens must remain useful when metadata is partial and must not silently fall back to unrelated raw-NFT view logic.

## Validation

Open item and collection detail from Music, preserve graceful partial-metadata handling, and keep the screens scoped to browsing/detail work.

## Handoff Rule

If a requested enhancement is really about playback engine depth or playlist behavior, split it into later tickets instead of stretching `P0-452`.
