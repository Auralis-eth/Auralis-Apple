# P0-601 Strategy: Mode system (Observe v0)

## Status

Blocked

## Ticket

Implement the global Observe-only mode state, display it in chrome, persist it in app state, and include it in receipts.

## Dependencies

P0-101B, P0-501

## Strategy

- Formalize mode-state ownership after the chrome already exists.
- Keep the Phase 0 behavior locked to Observe.
- Add receipt inclusion here rather than hiding it in random feature layers.

## Key Risk

Avoid incorrect mode state after restore and avoid confusing users with disabled future mode-switch UI.

## Definition Of Done

- Global mode-state ownership is explicit.
- The chrome uses the formal mode source of truth.
- Receipts include mode=Observe where required.

## Validation Target

Mode badge always shows Observe, receipts include mode=Observe, and any execute placeholder is denied and logged.
