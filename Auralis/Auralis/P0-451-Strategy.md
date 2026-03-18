# P0-451 Strategy: Music library index + storage (v0)

## Status

Partially blocked

## Ticket

Implement a minimal music library index with local persistence and refresh receipts, using demo data or a lightweight local index for Phase 0.

## Dependencies

P0-101A, P0-101E, P0-501, P0-502 slices

## Strategy

- Start with deterministic demo or local-backed index data.
- Keep the initial index useful to Home and Search even before the full context stack is complete.
- Layer deeper integration later rather than holding the whole ticket.

## Key Risk

Support empty datasets, duplicate items, and corrupt demo index files without crashing or losing a usable shell.

## Definition Of Done

- The music index is real and locally usable.
- Home and Search can consume it before every later library surface is complete.
- Later context integration can attach cleanly.

## Validation Target

Load the library, persist local state across relaunch if needed, and emit receipts on refresh.
