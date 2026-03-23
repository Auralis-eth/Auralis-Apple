# P0-302 Strategy: Caching + freshness primitives

## Status

Completed for the current Phase 0 freshness contract

## Ticket

Implement cache entries with timestamps, TTL policy, stale detection, refresh triggers, and context-sheet-facing last-updated values.

## Dependencies

P0-301, P0-401, P0-502

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Retain cached data when refresh fails, avoid negative freshness after time shifts, and coalesce duplicate in-flight fetches.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Completion Note

The active Phase 0 caching and freshness slice is now complete for:

- TTL-backed freshness metadata flowing into `ContextSnapshot`
- stale detection with future-timestamp clamping
- retained last-successful refresh timestamps when a later refresh fails
- duplicate in-flight NFT refresh coalescing for the same active scope
- a single shared freshness label contract owned by `ContextFreshness`
- UI-facing freshness values in the context inspector

What remains intentionally downstream:

- broader context-service orchestration in `P0-402`
- fuller stale/offline shell behavior owned by `P0-101C` and `P0-403`
- additional cache-backed feature surfaces beyond the active NFT flow

## Validation Target

Store cache on first fetch, mark stale after TTL expiry, refresh timestamps correctly, preserve cached stale values on refresh failure with a receipt, and keep the inspector-facing freshness copy aligned with the shared model contract.
