# P0-103A Tickets And Session Handoff

## Summary

Implement the search entry points that make global search feel like a real shell-owned surface.

## Ticket Status

Startable.

## Execution Checklist

### 1. Confirm the launch surfaces

- [ ] Re-read `P0-103A-Strategy.md` and `P0-103A-Dependency-Note.md`.
- [ ] Confirm which shell and Home surfaces should open search.
- [ ] Confirm the canonical search route/root to use.

### 2. Implement the entry points

- [ ] Add the first search launch affordances.
- [ ] Route all entry points into the same search root.
- [ ] Keep the launch behavior consistent across surfaces.

### 3. Cover required edge cases

- [ ] Search still opens correctly when launched from sparse-data surfaces.
- [ ] Search entry points do not create parallel navigation states.
- [ ] The launch contract remains stable for later deep-link and resolution work.

### 4. Validate the vertical slice

- [ ] Verify each entry point lands on the same search root.
- [ ] Verify search is discoverable without cluttering the shell.
- [ ] Record any later search-result/history work outside this ticket.

## Critical Edge Case

Search entry points must not fragment the app into multiple inconsistent search-launch contracts.

## Validation

Open search from the intended surfaces and preserve one canonical search entry contract.

## Handoff Rule

If a proposed change is really about search results or resolution, move it to the later search tickets instead of stretching `P0-103A`.
