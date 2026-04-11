# P0-461 Dependency Note

## Status

Implemented for the provider-backed holdings slice. Native balance, provider-backed ERC-20 retrieval, scoped SwiftData persistence, and honest degraded-state handling are all present in the active shell path.

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
- The active `P0-461` route now also uses the existing Alchemy-backed read-only provider layer for account-scoped ERC-20 holdings retrieval and enrichment.
- The current `TokenHolding` model and `TokenHoldingsStore` remain the stable persistence seam for this provider-backed slice.

## Rule For Planning

Do not block the first holdings surface on full ERC-20 enrichment, richer token metadata, or final token-detail work.

Follow-on planning note:

Do explicitly track richer pricing, valuation, and history work as unfinished so later token tickets do not over-claim `P0-461`. Provider-backed ERC-20 holdings retrieval itself is now part of the landed slice.
