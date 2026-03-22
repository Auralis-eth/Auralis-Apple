# P0-701A Dependency Note

## Status

Startable

## Dependencies

- P0-101A
- P0-301
- P0-402

## Why It Is Blocked

This ticket can start earlier than full enforcement, but it still needs enough real service shape to scaffold around.

## Safe Pre-Work

- Identify intended service seams.
- Prefer explicit dependency injection in new work.
- Avoid direct UI-to-provider shortcuts even before enforcement exists.

## Current Note

`P0-301` now provides an early injected provider seam, which means `P0-701A` no longer has to invent that layer from scratch. What is still missing is the broader context-service ownership from `P0-402`.

## Safe Work Now

- Centralize shell-facing service construction.
- Move UI code onto explicit service entry points where the dependencies already exist.
- Replace direct references to live receipt-store implementations with shared factory seams.

## Still Deferred

- Context-service ownership beyond the shell layer in `P0-402`
- Stronger boundary enforcement and anti-bypass rules in `P0-701B`

## Unblock Condition

There is enough provider and context-service shape to scaffold the structure without inventing a fake architecture.
