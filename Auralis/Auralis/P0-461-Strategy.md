# P0-461 Strategy: Token holdings list (v0)

## Status

Partially blocked

## Ticket

Implement the token holdings list for the active account and chain scope, with ETH minimum support and optional ERC-20 support.

## Dependencies

P0-301, P0-302, P0-402, P0-502 slices

## Strategy

- Allow local or placeholder holdings data first.
- Layer provider-backed enrichment after the holdings surface exists.
- Keep the UI and model shape stable across the transition from placeholder to real data.

## Key Risk

Handle ETH-only lists, missing token metadata, stale cached balances after fetch failure, and the transition from placeholder to provider-backed data.

## Definition Of Done

- The holdings surface exists and is usable.
- Placeholder data can later be replaced by provider-backed data without a redesign.
- Freshness and receipt integration can layer in incrementally.

## Validation Target

Display native ETH balance, refresh with receipts and freshness updates, and show cached stale balances in offline mode.
