# P0-461 Strategy: Token holdings list (v0)

## Status

Implemented for the native-balance-first slice. Manual UI QA and provider-backed ERC-20 enrichment remain follow-on work.

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

## Implemented Slice

- The ERC-20 tab now mounts a real holdings surface instead of the placeholder screen.
- Native balance persists into SwiftData-backed `TokenHolding` records scoped by normalized account address and chain.
- The screen reads persisted holdings rows for the active scope and keeps cached native state visible when a later refresh does not produce a fresh balance value.
- The holdings row contract is in place for later ERC-20 enrichment without forcing a surface rewrite.

## Follow-On Work

- Add a provider-backed API call that returns token holdings for an account so ERC-20 rows can be populated from a real source instead of remaining native-only or placeholder-backed.
- Attach that provider-backed holdings refresh path to the existing scope, freshness, and receipt seams instead of inventing a parallel token pipeline.
- Keep token detail and richer enrichment behavior out of `P0-461`; those remain follow-on tickets.

## Key Risk

Handle native-only lists, missing token metadata, stale cached balances after fetch failure, and partial provider coverage without breaking the shell.

## Definition Of Done

- A holdings list exists for the active scope.
- Native balance is visible and understandable.
- The surface survives missing or partial token metadata.
- Later enrichment can attach without redesigning the list contract.
- Follow-on provider-backed token holdings API work is explicitly deferred rather than being implied complete.

## Validation Target

Display native balance, preserve usable cached state when refresh fails, and leave a clean seam for later token-detail routing.
