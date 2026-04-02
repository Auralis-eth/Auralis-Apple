# P0-462 Tickets And Session Handoff

## Summary

Implement the token detail screen that deepens the holdings list into a real per-token destination.

## Ticket Status

Partially blocked behind the stable `P0-461` holdings-row contract, but prep work is still legitimate.

## Execution Checklist

### 1. Confirm the holdings-to-detail contract

- [ ] Re-read `P0-462-Strategy.md` and `P0-462-Dependency-Note.md`.
- [ ] Confirm which row types from `P0-461` should open token detail.
- [ ] Confirm the minimum metadata contract for native and token rows.

### 2. Implement the first token detail screen

- [ ] Add the route and screen shell for token detail.
- [ ] Render the minimum token identity, balance, and scope information.
- [ ] Preserve honest partial-data behavior.

### 3. Cover required edge cases

- [ ] Native-only tokens remain understandable.
- [ ] Missing symbol/name/logo metadata does not break the screen.
- [ ] Later enriched fields can attach without redesigning the screen.

### 4. Validate the vertical slice

- [ ] Verify token detail opens from supported holdings rows.
- [ ] Verify sparse metadata remains understandable.
- [ ] Record any later pricing/history additions outside this ticket.

## Critical Edge Case

The token detail screen must remain useful even when token metadata is incomplete or only a native-balance row exists.

## Validation

Open token detail from the holdings list and keep the screen stable across native-only and sparse-metadata cases.

## Handoff Rule

If the holdings-row contract is still moving, keep this ticket at the route/screen-shell level and avoid premature detail-model lock-in.
