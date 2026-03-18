# P0-101C Strategy: Context Bar behavior + interactions

## Status

Blocked

## Ticket

Wire the chrome freshness and scope UI to Context Builder, support stale detection, and open Context Inspector from the chrome with consistent refresh behavior.

## Dependencies

P0-101B, P0-401, P0-402, P0-403, P0-302

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Context build failure, TTL expiry mid-navigation, and rapid account switching must not produce spinner loops, stale overwrites, or incorrect scope display.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Tap freshness pill to open inspector, force stale timestamps, refresh from chrome, and switch accounts rapidly without showing duplicated or incorrect context.
