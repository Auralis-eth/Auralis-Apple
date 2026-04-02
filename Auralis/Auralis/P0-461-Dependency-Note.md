# P0-461 Dependency Note

## Status

Startable

## Dependency Read

- `P0-301` is complete enough for read-only provider-backed native balance work.
- `P0-302` may deepen token-provider abstraction later, but it does not need to block the first holdings surface.
- `P0-402` is complete enough for shell/context freshness attachment when the holdings slice is ready to use it.
- `P0-502` already provides the receipt foundation this ticket can extend.

## Safe First Slice

- Ship the holdings surface with native balance minimum support.
- Allow local, cached, or placeholder token rows before full ERC-20 enrichment is available.
- Keep the list model and row contract stable across that transition.

## Rule For Planning

Do not block the first holdings surface on full ERC-20 enrichment, richer token metadata, or final token-detail work.
