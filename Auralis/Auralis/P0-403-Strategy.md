# P0-403 Strategy: Context inspector UI

## Status

Completed for the current receipt-aware inspector slice

## Ticket

Add the Why-am-I-seeing-this inspector with scope, provenance, freshness, and links to related receipts.

## Dependencies

P0-101C, P0-402, P0-503

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Inspector should still work with no receipts, large details need collapse behavior, and stale offline context must be labeled clearly.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Open from major screens, verify freshness and provenance display against real cache state, and navigate into linked receipt detail.

## Completion Note

- the context inspector now includes a dedicated Why-am-I-seeing-this section tied to the active shell scope summary
- the inspector now surfaces the latest related `context.built` receipt for the active scope when one exists
- the inspector can now route directly into receipt detail from that linked receipt
- the no-receipt path remains explicit instead of showing placeholder links

## Remaining Work

- broaden receipt linkage beyond the latest context-build receipt only if richer grouping becomes necessary
- add collapse behavior only if the inspector grows beyond the current lightweight vertical slice
- reserve fuller receipt export or timeline shortcuts for downstream receipt-surface work
