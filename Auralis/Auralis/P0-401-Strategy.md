# P0-401 Strategy: Context schema v0 (graph-lite)

## Status

Complete

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
- The schema now carries real local counts for tracked NFTs, playlists, and scoped receipts where that data already exists in local storage.
- The schema now records whether the active account is running through the guest-pass path instead of hard-coding that preference to false.
- The chrome inspector reads the new snapshot instead of the older ad hoc shape and now exposes library, preference, balance, provenance, and freshness sections from the shared contract.
- Provider-backed native balance display now flows through `ContextService` for supported scopes.
- The chrome mode and context affordances now read mode/freshness labels from `ContextSnapshot` instead of mixing in separate ad hoc shell values.
- Shell empty-library messaging can now describe the active scope from the shared snapshot where that scope is already available.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Build minimal valid snapshots, verify provenance and timestamps for populated fields, and confirm persistence serialization if stored.

## Completion Boundary

`P0-401` is complete for the current Phase 0 context-contract slice.

The context contract now carries real shell-owned local preference state for pinned Home quick links, the chrome and inspector consume the shared snapshot, and Home-facing UI now deepens the same schema instead of bypassing it with parallel shell lookups.

Later tickets may still broaden the schema, but that work is additive rather than a blocker for closing this ticket.
