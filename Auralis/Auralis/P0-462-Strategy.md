# P0-462 Strategy: Token detail screen

## Status

Completed for the current slice

## Ticket

Implement the token detail screen that deepens the holdings list into a real per-token destination.

## Dependencies

- `P0-461`
- `P0-101A`
- `P0-301`
- `P0-403` slice

## Strategy

- Reuse the landed `P0-461` holdings-row contract instead of inventing a second token detail model.
- Build the first token detail screen on the mounted `ERC20TokenRoute` and scoped `TokenHolding` lookup.
- Keep the screen resilient to missing token metadata and partial provider coverage.

## Key Risk

Avoid letting the token detail screen imply full ERC-20 enrichment when the current holdings contract is still local-first and metadata-light.

## Definition Of Done

- A token detail destination exists for the first supported ERC-20 holdings rows.
- Missing metadata degrades honestly.
- The screen leaves room for later enrichment without redesign.
- Focused unit coverage protects the sparse-data and fallback presentation contract.

## Validation Target

Open token detail from the holdings list, preserve understandable state for native-only or metadata-light tokens, and keep the detail contract stable for later enrichment.
