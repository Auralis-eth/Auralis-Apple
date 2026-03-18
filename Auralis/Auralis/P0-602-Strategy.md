# P0-602 Strategy: Policy gate wrapper for actions

## Status

Blocked

## Ticket

Create the Phase 0 PolicyGate that allows only read-only actions and denies any execute or signing path with receipts.

## Dependencies

P0-601, P0-502 slices, with structural alignment to `P0-701A` and later enforcement by `P0-701B`

## Strategy

- Build the gate after mode-state ownership is real.
- Align its seams with the structure-first rules from `P0-701A`.
- Let `P0-701B` later enforce the no-bypass path more strongly.

## Key Risk

Denied actions must have zero side effects, while allowed actions stay predictable and auditable.

## Definition Of Done

- PolicyGate owns allow and deny behavior for Phase 0 actions.
- It fits the intended early structure.
- Later enforcement and smoke tests can build on it cleanly.

## Validation Target

Audit action handlers, verify denied actions log policy receipts, and confirm allowed actions still proceed and log correctly.
