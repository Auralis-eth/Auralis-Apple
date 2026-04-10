# P0-101C Strategy: Context Bar behavior + interactions

## Status

Complete

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

Open the inspector from chrome, force stale timestamps, refresh from the inspector freshness section, and switch accounts rapidly without showing duplicated or incorrect context.

## Current Slice

- the shell still uses a dedicated Context entry point from chrome instead of a separate freshness pill, by product choice
- the inspector freshness section now shows stale labeling from `ContextSnapshot`
- the inspector freshness section now offers an explicit refresh action when the active scope is stale, unknown, or has not completed a successful refresh yet
- the refresh action routes through the existing shell refresh path instead of inventing a second local context-refresh flow

## Remaining Work

`P0-101C` is complete under the current context-sheet interpretation.

Chrome now surfaces scope and freshness state visibly, stale detection and refresh continue to route through the shared shell path, and the inspector remains the dedicated interaction point for deeper context details.
