# P0-101D Strategy: Global error + empty-state patterns (shell-level)

## Status

Implemented

## Ticket

Create shared shell-level empty and error patterns for first-run, provider failure, no receipts, and empty library states.

## Dependencies

P0-101E

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Avoid banner stacking, preserve partial cached content on refresh failure, and clearly label demo content on first-run paths.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Completion Note

Implemented as a shared shell-status foundation in `Aura/ShellStatusView.swift` and integrated into:

- gateway first-run guidance
- account-switcher empty state
- newsfeed empty state and provider-failure fallback banner
- music library empty state
- NFT library empty state

The current Phase 0 result is intentionally narrow:

- no standalone receipts screen was added here
- a reusable no-receipts state exists for later `P0-503` integration
- cached content is preserved on newsfeed refresh failure instead of replacing the entire surface with a hard error

## Validation Target

Launch with no accounts, disable network while cached data exists, open receipts with none, and verify the library empty state offers only safe actions.
