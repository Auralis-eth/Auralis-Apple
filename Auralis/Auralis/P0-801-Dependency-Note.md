# P0-801 Dependency Note

## Status

Startable

## Dependency Read

- `P0-101D` already established the demo-data baseline strongly enough for a real Phase 0 follow-on.
- Active shell/context/receipt work now provides enough provenance shape to describe offline vs demo behavior honestly.

## Safe First Slice

- Define deterministic bundled demo data and offline behavior rules together.
- Keep demo/live/cached provenance explicit.
- Avoid creating shadow data paths that bypass the normal shell contracts.
- Gate demo entry to non-production builds even though it is launched from the address-entry screen.

## Rule For Planning

Do not treat offline mode as just \"provider failed\" if the product wants a deliberate post-entry offline experience, and do not let real-address flows fall through to demo data.
