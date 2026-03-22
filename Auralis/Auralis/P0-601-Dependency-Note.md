# P0-601 Dependency Note

## Status

Implemented

## Blocking Dependencies

- none

## Why It Was Previously Blocked

The agreed order was:

1. deliver `P0-101B` first with fixed Observe presentation
2. formalize mode-state ownership and receipt inclusion here

That sequencing work is now complete.

## Safe Pre-Work

- define the final owner of global mode state
- define how mode is represented in receipts
- avoid spreading pseudo-mode state across feature views

## Current State

The chrome exists, `ModeState` owns the formal Observe value, and receipt/policy seams now use that mode explicitly.
