# P0-401 Dependency Note

## Status

Complete

## Dependencies

- P0-201
- P0-204
- P0-302

## Dependency Read

- `P0-201` is complete enough for the current schema inputs.
- `P0-204` is complete enough to provide a real chain-scope field.
- `P0-302` is complete enough for the current freshness contract used by the shell-facing snapshot, even if downstream policy cleanup may still evolve.

## Delivered Contract

- `ContextSnapshot` is the real shell-facing context schema and remains versioned at `p0.context.v0`.
- Scope, freshness, balances, library pointers, module pointers, and local preferences now all have real owned inputs.
- The shell chrome and context inspector read the shared snapshot contract instead of ad hoc shell values.
- Home now consumes the shared snapshot for scoped launcher and pinned-link copy instead of freelancing that copy from local bindings.

## Completion Read

- `P0-201` provides the persisted account identity inputs the schema needs.
- `P0-204` provides the live chain-scope truth the schema now carries through the shared snapshot.
- `P0-302` provides the TTL-backed freshness contract already exposed in the snapshot and inspector.

## Remaining Work That Is Not A P0-401 Blocker

- Any later additive schema growth for future product surfaces
- Any follow-on freshness-policy tuning in the broader `P0-301` / `P0-302` / `P0-402` family
- Richer inspector storytelling beyond the current baseline contract
