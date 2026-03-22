# P0-401 Strategy: Context schema v0 (graph-lite)

## Status

In Progress

## Ticket

Define the scoped ContextSnapshot schema for active account, chain scope, summary balances, module pointers, preferences, provenance, and freshness.

## Dependencies

P0-201, P0-204, P0-302

## Strategy

- Keep the implementation narrow and phase-correct.
- Start with a schema-first slice that formalizes the context contract without inventing provider data.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.
- Preserve compatibility for the current shell inspector while the broader Context Builder stack is still pending.

## Key Risk

Missing values must remain valid, provenance rules must stay consistent, and the schema must stay deterministic for a given scope and cache state.

## Current Slice

- `ContextSnapshot` now exists as the Phase 0 context contract.
- The live shell context source produces typed scope, provenance-bearing fields, library pointers, local preferences, and freshness metadata.
- The chrome inspector reads the new snapshot instead of the older ad hoc shape.
- Native balance, receipt linkage, and TTL-backed stale evaluation remain deferred until `P0-301`, `P0-302`, and `P0-402`.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Build minimal valid snapshots, verify provenance and timestamps for populated fields, and confirm persistence serialization if stored.

## Completion Boundary

This ticket can now progress as a schema-first implementation, but it should not be marked fully complete until `P0-302` provides the real freshness contract used for stale evaluation and downstream context behavior.
