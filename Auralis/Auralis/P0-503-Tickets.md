# P0-503 Tickets And Session Handoff

## Summary

Build the receipts timeline with filtering, search, pagination, and structured receipt detail with related-receipt links by correlation ID.

## Explicit Task List

- Confirm the upstream unblock condition for `P0-501`, `P0-101A`, and `P0-101E` before building product UI.
- Define the receipt-list screen state model for scoped loading, empty state, filter state, search query, and pagination cursor or page boundary.
- Mount a real receipts timeline screen in the app shell using the shared navigation and design primitive baseline instead of throwaway scaffolding.
- Render the first page of receipts with stable ordering, timestamp, status, summary, and enough metadata to distinguish similar events.
- Add scope-aware empty state behavior so account changes or missing receipts do not produce ambiguous blank screens.
- Implement filter controls for the supported receipt dimensions and make the default filter state obvious after scope changes.
- Implement receipt search across the intended key fields without leaking storage or query details into the view layer.
- Add pagination or incremental loading behavior that keeps large receipt histories usable without replacing the screen state model later.
- Build a structured receipt detail view that presents sanitized payload information in a readable hierarchy.
- Add related-receipt navigation by correlation ID so multi-step flows can be followed from one receipt to its siblings.
- Verify receipt detail and related-receipt navigation integrate cleanly with downstream inspector and Home recent-activity surfaces.
- Validate empty state, large-volume behavior, default filter clarity after account scope changes, and receipt-detail navigation before calling the ticket complete.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Handle empty state, large volumes, and default filter clarity when account scope changes.

## Validation

Load and filter the list, open receipt detail and related receipts, search by key fields, and validate empty and large list behavior.

## Handoff Rule

If this ticket is still blocked when work starts, do not build throwaway scaffolding unless the dependency note explicitly allows it.
