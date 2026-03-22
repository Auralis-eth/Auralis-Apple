# P0-401 Dependency Note

## Status

Startable

## Dependencies

- P0-201
- P0-204
- P0-302

## Dependency Read

- `P0-201` is complete enough for the current schema inputs.
- `P0-204` is complete enough to provide a real chain-scope field.
- `P0-302` is still not ready, so freshness can only be modeled as metadata, not final TTL-driven state.

## Safe Work Now

- Define the typed `ContextSnapshot` schema and version it.
- Move the shell inspector to the new snapshot contract.
- Model provenance and timestamps using existing local values.
- Keep balance and module sections placeholder-safe instead of fabricating provider-backed data.

## Still Deferred

- TTL policy and stale evaluation from `P0-302`
- Real provider-backed balance summary from `P0-301`
- Context-build orchestration and receipt linkage from `P0-402`

## Full Completion Condition

The ticket is fully complete when the schema no longer relies on ad hoc freshness behavior and the remaining deferred fields are fed by the real context/provider stack instead of placeholder-safe empty values.
