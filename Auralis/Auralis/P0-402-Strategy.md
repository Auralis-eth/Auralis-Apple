# P0-402 Strategy: Context service + dependency boundaries

## Status

Blocked

## Ticket

Implement ContextService as the only UI entry point for scoped context, coordinating provider reads, cache use, snapshot assembly, and receipts.

## Dependencies

P0-401, P0-301, P0-302, the needed `P0-502` slices, and early structural scaffolding from `P0-701A`

## Strategy

- Build the service only after the provider, cache, and schema shapes are real.
- Align it with `P0-701A` structural boundaries from the start.
- Let `P0-701B` later enforce the intended direction more strictly.

## Key Risk

Rapid account switches, coalesced requests, and partial snapshot failure must work without stale overwrites or direct provider leakage into UI.

## Definition Of Done

- ContextService is the intended UI-facing entry point.
- Its shape fits early structural scaffolding.
- Later enforcement can lock the boundaries down without redesigning the service.

## Validation Target

Request context from UI, observe cached-then-refresh updates, switch active account without stale overwrites, and confirm the service shape supports boundary enforcement.
