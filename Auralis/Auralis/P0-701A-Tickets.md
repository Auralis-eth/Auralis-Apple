# P0-701A Tickets And Session Handoff

## Summary

Early structural scaffolding for layered boundaries.

## Execution Order

1. Identify the main service seams the UI should talk to.
2. Shape code ownership so lower-layer dependencies are not reached directly from views.
3. Introduce dependency-injection points where future enforcement will rely on them.
4. Record the follow-on boundaries that still depend on `P0-402` and `P0-701B`.

## Critical Edge Case

Do not freeze the codebase into fake module boundaries before the real service APIs exist.

## Validation

Confirm that new work routes through explicit services and seams rather than direct provider or storage access from UI code.

## Handoff Rule

This ticket prepares the structure. It should not pretend compile-time enforcement is already solved, but it should leave obvious live service seams that new work can use immediately.

## Latest Completion Note

- added a shell-facing library-context provider seam so `ContextService` inputs no longer require `MainTabView` to fetch `Playlist` and `StoredReceipt` models itself
- kept the change narrow by routing only the existing context-library count reads through that seam, rather than broadening it into a full storage abstraction pass
- left deeper read-path enforcement and feature-wide boundary cleanup for `P0-701B` and later service-layer work
