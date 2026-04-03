# P0-461 Dependency Note

## Status

Implemented for the native-balance-first slice. Provider-backed token holdings retrieval remains a planned follow-on.

## Dependency Read

- `P0-301` is complete enough for read-only provider-backed native balance work.
- `P0-302` may deepen token-provider abstraction later, but it does not need to block the first holdings surface.
- `P0-402` is complete enough for shell/context freshness attachment when the holdings slice is ready to use it.
- `P0-502` already provides the receipt foundation this ticket can extend.

## Safe First Slice

- Ship the holdings surface with native balance minimum support.
- Allow local, cached, or placeholder token rows before full ERC-20 enrichment is available.
- Keep the list model and row contract stable across that transition.

## Current Read

- `P0-301` was sufficient for the native-balance provider seam used by the first holdings slice.
- The missing dependency for fuller ERC-20 behavior is not shell routing or SwiftData storage anymore; it is a provider-backed token holdings API call for account-scoped token inventory.
- That provider-backed holdings call should be introduced as a follow-on seam above or alongside the current read-only provider layer, then persisted into the existing `TokenHolding` model.

## Rule For Planning

Do not block the first holdings surface on full ERC-20 enrichment, richer token metadata, or final token-detail work.

Follow-on planning note:

Do explicitly track provider-backed token holdings retrieval as unfinished work so later token tickets do not assume ERC-20 data is already available from the network layer.
