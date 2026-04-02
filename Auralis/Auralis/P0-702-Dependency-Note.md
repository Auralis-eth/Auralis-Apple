# P0-702 Dependency Note

## Status

Startable

## Dependency Read

- `P0-401` already provides enough shared shell/context truth to distinguish trusted shell-owned values from external ones.
- `P0-602` helps where labeling and action policy intersect.
- Search, deep-link, and provider-backed surfaces are the obvious first targets.

## Safe First Slice

- Define the label contract first.
- Apply it to the highest-value surfaces next.
- Keep the rule reusable for later safety and bypass testing.

## Rule For Planning

Do not bury trust labeling inside one-off view copy or styling hacks.
