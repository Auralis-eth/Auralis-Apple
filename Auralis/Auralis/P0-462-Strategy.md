# P0-462 Strategy: Token detail screen

## Status

Partially blocked

## Ticket

Implement the token detail screen that deepens the holdings list into a real per-token destination.

## Dependencies

- `P0-461`
- `P0-101A`
- `P0-301`
- `P0-403` slice

## Strategy

- Let the holdings list establish the first row contract before overcommitting to token detail shape.
- Build native-token and ERC-20 detail presentation on a shared structure where practical.
- Keep the first screen resilient to missing token metadata and partial provider coverage.

## Key Risk

Avoid designing the token detail screen around data that the holdings list does not reliably provide yet.

## Definition Of Done

- A token detail destination exists for the first supported holdings rows.
- Missing metadata degrades honestly.
- The screen leaves room for later enrichment without redesign.

## Validation Target

Open token detail from the holdings list, preserve understandable state for native-only or metadata-light tokens, and keep the detail contract stable for later enrichment.
