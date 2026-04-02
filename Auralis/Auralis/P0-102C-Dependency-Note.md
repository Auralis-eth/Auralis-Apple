# P0-102C Dependency Note

## Status

Startable

## Dependency Read

- `P0-102A` already created the modules section and its structural slot.
- `P0-101A` and existing router work are sufficient for real shortcut routing.
- `P0-201` account state is already enough for modules that depend on the active account.

## Safe First Slice

- Improve the current modules section rather than replacing it.
- Use real routes and a stable launcher contract.
- Leave unfinished future module ideas out of the first pass.

## Rule For Planning

Do not turn this ticket into a full Home redesign or into implementation of every downstream feature the shortcuts point toward.
