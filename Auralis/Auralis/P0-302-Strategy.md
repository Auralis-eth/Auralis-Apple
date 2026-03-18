# P0-302 Strategy: Caching + freshness primitives

## Status

Blocked

## Ticket

Implement cache entries with timestamps, TTL policy, stale detection, refresh triggers, and UI-facing last-updated values.

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

## Validation Target

Store cache on first fetch, mark stale after TTL expiry, refresh timestamps correctly, and preserve cached stale values on refresh failure with a receipt.
