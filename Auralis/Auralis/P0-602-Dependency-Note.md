# P0-602 Dependency Note

## Status

Startable

## Dependency Read

- `P0-601` already established the Observe-mode ownership baseline.
- `P0-101A` provides the shell ownership/routing context where a gate can live cleanly.
- `P0-502` already supports receipt-backed action-denial recording where needed.

## Safe First Slice

- Wrap a representative subset of actions through the shared policy gate.
- Keep the gate explicit and centrally owned.
- Extend to more surfaces later instead of forcing full-app coverage in one pass.

## Rule For Planning

Do not scatter policy checks back into view-local action handlers once the wrapper contract exists.
