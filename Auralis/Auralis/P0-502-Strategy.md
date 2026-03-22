# P0-502 Strategy: Receipt logging integration points

## Status

Completed for the active account and chain-scope slice

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

## Completion Note

The active Phase 0 receipt slice is now complete for:

- account activation, selection, and removal flows
- account chain-scope changes
- correlation continuity between current-chain change receipts and the follow-on NFT refresh flow

What remains intentionally deferred:

- broad cross-feature audit
- deduping and naming cleanup
- repo-wide verification beyond the active delivered slice

## Validation Target

Run the relevant feature flow, verify expected receipts exist, and confirm correlation links are correct where the local slice needs them.
