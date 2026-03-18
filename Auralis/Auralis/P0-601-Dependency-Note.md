# P0-601 Dependency Note

## Status

Blocked by sequencing, not deadlock

## Blocking Dependencies

- P0-101B
- P0-501

## Why It Is Blocked

The agreed order is:

1. deliver `P0-101B` first with fixed Observe presentation
2. formalize mode-state ownership and receipt inclusion here

## Safe Pre-Work

- define the final owner of global mode state
- define how mode is represented in receipts
- avoid spreading pseudo-mode state across feature views

## Unblock Condition

The chrome exists and the system is ready to replace fixed Observe presentation with formal mode-state ownership.
