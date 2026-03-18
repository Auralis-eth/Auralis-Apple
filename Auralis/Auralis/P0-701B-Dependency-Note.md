# P0-701B Dependency Note

## Status

Blocked

## Blocking Dependencies

- P0-602
- P0-701A
- P0-402

## Why It Is Blocked

This is the enforcement pass, so it must wait until the real service and policy seams are already present.

## Safe Pre-Work

- Keep new code aligned with the intended seam structure.
- Record known bypass paths for later enforcement cleanup.

## Unblock Condition

Structural scaffolding and the main service graph are in place, making real enforcement practical instead of speculative.
