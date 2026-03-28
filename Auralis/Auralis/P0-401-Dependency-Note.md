# P0-401 Dependency Note

## Status

In Progress

## Dependencies

- P0-201
- P0-204
- P0-302

## Dependency Read

- `P0-201` is complete enough for the current schema inputs.
- `P0-204` is complete enough to provide a real chain-scope field.
- `P0-302` is complete enough for the current freshness contract used by the shell-facing snapshot, even if downstream policy cleanup may still evolve.

## Safe Work Now

- Define the typed `ContextSnapshot` schema and version it.
- Move the shell inspector to the new snapshot contract.
- Model provenance and timestamps using existing local values.
- Feed schema sections from real local values where the app already owns them.
- Keep balance and any not-yet-real provider sections placeholder-safe instead of fabricating provider-backed data.

## Still Deferred

- Broader downstream adoption beyond the current shell and inspector path
- Any follow-on freshness-policy cleanup if ownership shifts later in the `P0-301` / `P0-302` / `P0-402` family
- Remaining placeholder-safe preference or module fields whose owning product surfaces are not finalized yet

## Full Completion Condition

The ticket is fully complete when the remaining deferred fields are fed by the real context/provider stack instead of placeholder-safe empty values, without relying on temporary placeholder-safe sections that have no settled owner yet.
