# P0-701A Dependency Note

## Status

Partially blocked

## Blocking Dependencies

- P0-101A
- P0-301
- P0-402

## Why It Is Blocked

This ticket can start earlier than full enforcement, but it still needs enough real service shape to scaffold around.

## Safe Pre-Work

- Identify intended service seams.
- Prefer explicit dependency injection in new work.
- Avoid direct UI-to-provider shortcuts even before enforcement exists.

## Unblock Condition

There is enough provider and context-service shape to scaffold the structure without inventing a fake architecture.
