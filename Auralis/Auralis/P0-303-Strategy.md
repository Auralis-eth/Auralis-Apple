# P0-303 Strategy: Error handling & degraded mode

## Status

Completed for the active NFT provider-failure and degraded-mode slice

## Ticket

Define unified provider and degraded-mode errors so the app stays navigable through offline, parsing, and rate-limit failures.

## Dependencies

P0-301, P0-302, the needed `P0-502` slices, with `P0-101D` as a recommended parallel foundation

## Strategy

- Treat provider and cache behavior as the real gate.
- Use `P0-101D` to standardize the visible shell language once the degraded-mode semantics exist.
- Do not let visual pattern work replace actual degraded-mode policy.

## Key Risk

Partial failures must preserve usable UI, and retry or refresh behavior must not spiral into loops.

## Definition Of Done

- The degraded-mode semantics are clear and stable.
- UI remains navigable through partial or offline failure.
- Final shell presentation can align with `P0-101D`.

## Completed Slice

- `NFTService` now exposes typed provider-failure semantics instead of forcing shell UI to branch on raw `Error?`.
- Newsfeed empty and cached-content states now read from the same degraded-mode contract for offline, rate-limit, invalid-response, and unavailable failures.
- NFT refresh failure receipts now persist structured failure metadata (`errorKind`, retryability) alongside the sanitized error string.
- Focused tests cover offline classification, rate-limit presentation, retained cached-content behavior, and receipt payload recording.

## Validation Target

Simulate offline and rate-limit conditions, verify receipts for failures, and confirm partial UI remains available without crashes.
