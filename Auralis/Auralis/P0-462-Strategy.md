# P0-462 Strategy: Token detail screen (v0)

## Status

Blocked

## Ticket

Create the token detail screen for native and ERC-20 assets with provenance, freshness, safe copy, and explorer links.

## Dependencies

P0-461, P0-103D, P0-502, P0-702

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Adapt the UI for native assets with no contract, unknown decimals, and invalid or empty contract addresses.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Open from the token list, log copy and explorer actions, and verify provenance badges match the underlying source.
