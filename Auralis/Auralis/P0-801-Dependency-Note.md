# P0-801 Dependency Note

## Status

Canceled

## Dependency Read

No downstream ticket should wait on `P0-801`.

The earlier dependency story assumed a bundled demo-data and dedicated offline-mode follow-on. That assumption is now intentionally invalid. Phase 0 should depend on the normal live/cached shell contracts, not on a second demo-data path.

## Planning Rule

When a later ticket mentions offline behavior, interpret it as:

- use persisted local state where it already exists
- keep provider failure and stale-state messaging honest
- do not invent fixture-backed substitute content unless a new ticket explicitly requires it
