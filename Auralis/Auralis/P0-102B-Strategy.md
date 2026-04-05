# P0-102B Strategy: Active account summary card

## Status

Completed for the current slice

## Ticket

Deepen the active account summary card on Home so it feels like a real shell-owned identity surface instead of a decorative placeholder.

## Dependencies

- `P0-102A`
- `P0-201`
- `P0-204`
- `P0-401` slices

## Strategy

- Build on the existing Home identity section rather than redesigning Home.
- Surface the most useful account and scope information first.
- Keep summary data honest when optional context fields are missing.
- Preserve the current scenic/glass visual language.

## Key Risk

Avoid overloading the summary card with too many half-trustworthy fields or coupling it too tightly to future deeper account/profile work.

## Definition Of Done

- Home has a stronger active account summary card.
- The card reflects real shell/account state.
- Missing optional data degrades cleanly.

## Validation Target

Show active account identity and useful scope summary without breaking Home when optional context or balance data is absent.

## Current Read

- The active account summary card is now a real Home identity surface backed by shell-owned account and scope fields.
- The current slice is validated with unit tests around fallback behavior, scope changes, and absence of richer optional data.
- Remaining work belongs to later profile-management or deeper account surfaces, not this baseline Home summary card ticket.
