# P0-461 Strategy: Token holdings list (v0)

## Status

Startable

## Ticket

Implement the first token holdings list for the active account and chain scope, with native balance minimum support and a clean path to later ERC-20 enrichment.

## Dependencies

- `P0-301`
- `P0-302`
- `P0-402`
- `P0-502` slices

## Strategy

- Start with a trustworthy holdings surface before chasing full enrichment depth.
- Treat native balance as the required minimum slice.
- Allow placeholder or local-backed ERC-20 rows if real provider-backed metadata is not ready yet.
- Keep the holdings row model stable so later enrichment does not force a surface rewrite.

## Key Risk

Handle native-only lists, missing token metadata, stale cached balances after fetch failure, and partial provider coverage without breaking the shell.

## Definition Of Done

- A holdings list exists for the active scope.
- Native balance is visible and understandable.
- The surface survives missing or partial token metadata.
- Later enrichment can attach without redesigning the list contract.

## Validation Target

Display native balance, preserve usable cached state when refresh fails, and leave a clean seam for later token-detail routing.
