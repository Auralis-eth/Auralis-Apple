# P0-103C Strategy: Resolution pipeline

## Status

Completed for the current slice

## Ticket

Implement the search resolution pipeline that turns raw queries into typed local or provider-backed search intents.

## Dependencies

- `P0-103A`
- `P0-201`
- `P0-301`
- `P0-302`

## Strategy

- Build the resolution layer as a contract between raw query input and later results UI.
- Prefer deterministic parsing and typed resolution over stringly-typed branching inside views.
- Allow local-first resolution where it is already trustworthy.

## Key Risk

Avoid hiding search behavior inside the UI layer or making the resolution contract too ad hoc to support later result categories.

## Definition Of Done

- Search queries resolve through a real pipeline.
- Local and provider-backed resolution seams are explicit.
- Later results/history/safety behavior can attach cleanly.

## Validation Target

Resolve supported query types deterministically and preserve a stable contract between query parsing and rendered results.
