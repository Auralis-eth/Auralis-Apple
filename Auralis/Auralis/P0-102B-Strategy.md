# P0-102B Strategy: Active account summary card

## Status

Startable

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
