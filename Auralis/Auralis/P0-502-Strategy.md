# P0-502 Strategy: Receipt logging integration points

## Status

Partially blocked

## Ticket

Integrate receipt logging across Phase 0 as incremental slices attached to each feature area.

Broad verification and cleanup are deferred to:

- `P0-502B` Receipt logging verification + cleanup

## Dependencies

P0-501, the specific feature slice being instrumented, and the local seam where receipts are emitted

## Strategy

- Do not wait for every feature to exist before adding receipts.
- Add the receipt slice that belongs to the feature currently being built.
- Reserve cross-feature audit, deduping, and cleanup for `P0-502B`.

## Key Risk

Avoid double-logging, preserve receipts in failure paths, and carry correlation IDs through chained flows without turning this into one giant end-stage ticket.

## Definition Of Done

- Feature-level receipt integration lands incrementally.
- Broad verification and cleanup are explicitly separated into `P0-502B`.

## Validation Target

Run the relevant feature flow, verify expected receipts exist, and confirm correlation links are correct where the local slice needs them.
