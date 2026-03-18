# P0-202 Dependency Note

## Status

Partially blocked

## Dependency Read

Hard dependency:

- `P0-201`

Recommended parallel foundation:

- `P0-101D`

## What This Means

Validation logic can start before the full shell-level error language is complete.

## Rule For Planning

Do not use `P0-101D` as the reason to defer address validation if the account model work is already ready.
