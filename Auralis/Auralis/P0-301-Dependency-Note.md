# P0-301 Dependency Note

## Status

Startable

## Dependencies

- P0-204

Structural alignment dependency:

- P0-701A

## Dependency Read

- `P0-204` is complete enough to provide the chain-aware input required by the provider seam.
- `P0-701A` is still only partial, so this ticket should establish injectable service seams without pretending full structural enforcement already exists.

## Safe Work Now

- Centralize provider endpoint and API-key resolution.
- Replace inline provider construction inside service-layer code with injected provider factories.
- Add native balance support as a provider capability even if no shell surface consumes it yet.

## Still Deferred

- Context-service ownership and receipt-backed provider orchestration in `P0-402`
- Freshness and TTL alignment in `P0-302`
- Full boundary enforcement in `P0-701B`
