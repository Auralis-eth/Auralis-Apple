# P0-402 Strategy: Context service + dependency boundaries

## Status

Completed for the active shell context slice

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

## Completion Note

The active Phase 0 context-service slice is now complete for:

- `ContextService` as the shell-facing UI entry point instead of direct `ContextSource` access
- cached snapshot ownership inside the service
- coalesced concurrent context requests for the same scope
- rapid account-switch isolation so stale requests do not overwrite the latest scope
- service-backed context inspection in the shell

What remains intentionally downstream:

- broader provider-backed substeps and partial-failure assembly beyond the current shell context inputs
- richer receipt-linked inspector behavior in `P0-403`
- stricter compile-time boundary enforcement in `P0-701B`

## Validation Target

Request context from UI, observe cached-then-refresh updates, switch active account without stale overwrites, and confirm the service shape supports boundary enforcement.
