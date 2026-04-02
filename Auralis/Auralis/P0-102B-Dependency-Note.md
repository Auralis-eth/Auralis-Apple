# P0-102B Dependency Note

## Status

Startable

## Dependency Read

- `P0-102A` already gives Home the structural slot for this card.
- `P0-201` and `P0-204` provide enough active-account and chain-scope truth for a meaningful first slice.
- `P0-401` exposes enough context fields to enrich the card without inventing new shell state.

## Safe First Slice

- Use already-owned account and context values.
- Prefer a few trustworthy summary fields over a long decorative profile dump.
- Keep profile-image generation and other temporary visuals in place if they are already part of the current Home language.

## Rule For Planning

Do not turn the active summary card into full profile management or a broader account-settings ticket.
