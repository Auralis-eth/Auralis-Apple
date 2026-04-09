# P0-103A Tickets And Session Handoff

## Summary

Implement the search entry points that make global search feel like a real shell-owned surface.

## Ticket Status

Completed for the current slice.

## Execution Checklist

### 1. Confirm the launch surfaces

- [x] Re-read `P0-103A-Strategy.md` and `P0-103A-Dependency-Note.md`.
- [x] Confirm which shell and Home surfaces should open search.
- [x] Confirm the canonical search route/root to use.

Launch-surface notes:

- The canonical search root remains the dedicated `search` tab.
- Existing shell and Home launch affordances now intentionally converge on that same root instead of drifting into alternate search flows.
- `GlobalChromeView` and `HomeTabView` continue to route through `router.showSearch()`, and the mounted `SearchRootView` now owns the rest of the search flow.

### 2. Implement the entry points

- [x] Add the first search launch affordances.
- [x] Route all entry points into the same search root.
- [x] Keep the launch behavior consistent across surfaces.

Implementation notes:

- The search tab remains the primary entry surface.
- Existing chrome and Home entry points now land on the same rooted search experience with no parallel navigation contract.
- Search owns downstream routing from inside `SearchRootView` rather than fragmenting launch behavior across tabs.

### 3. Cover required edge cases

- [x] Search still opens correctly when launched from sparse-data surfaces.
- [x] Search entry points do not create parallel navigation states.
- [x] The launch contract remains stable for later deep-link and resolution work.

### 4. Validate the vertical slice

- [x] Verify each entry point lands on the same search root.
- [x] Verify search is discoverable without cluttering the shell.
- [x] Record any later search-result/history work outside this ticket.

## Critical Edge Case

Search entry points must not fragment the app into multiple inconsistent search-launch contracts.

## Validation

Open search from the intended surfaces and preserve one canonical search entry contract.

## Handoff Rule

If a proposed change is really about search results or resolution, move it to the later search tickets instead of stretching `P0-103A`.
