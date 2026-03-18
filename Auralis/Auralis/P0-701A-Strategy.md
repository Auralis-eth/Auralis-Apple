# P0-701A Strategy: Layered Module Boundaries Structural Scaffolding

## Status

Partially blocked

## Ticket

Establish the early code-structure scaffolding that keeps UI, services, providers, policy, receipts, and storage moving toward clear separation before full enforcement is possible.

## Dependencies

P0-101A, P0-301, P0-402

## Strategy

- Start with folder, seam, and dependency-injection structure that supports later enforcement.
- Prefer explicit service entry points over direct UI access to lower layers.
- Avoid over-promising compile-time enforcement before the service graph is real.

## Key Risk

If this starts too late, feature tickets bake in cross-layer shortcuts that become expensive to unwind later.

## Definition Of Done

- Structural seams exist for the main read-only paths.
- UI-facing code has obvious service entry points.
- Later enforcement work can tighten rules without a full rewrite.

## Validation Target

Review imports, ownership, and dependency injection paths to ensure new feature work can build on the intended boundaries instead of bypassing them.
