# P0-102D Tickets And Session Handoff

## Summary

Deepen the Home recent-activity preview so it provides a real shell summary of recent actions and system events.

## Ticket Status

Startable.

## Execution Checklist

### 1. Confirm the preview source

- [ ] Re-read `P0-102D-Strategy.md` and `P0-102D-Dependency-Note.md`.
- [ ] Confirm which receipt/activity sources should feed the first preview.
- [ ] Confirm which deeper route the preview should open into.

### 2. Implement the recent-activity preview

- [ ] Render a lightweight recent-activity list or strip in Home.
- [ ] Keep the preview shorter and simpler than the full receipts surface.
- [ ] Route into richer history/detail when selected.

### 3. Cover required edge cases

- [ ] Empty activity history is shown honestly.
- [ ] Sparse or partial receipt data does not break the section.
- [ ] Preview rows remain understandable without requiring users to open the full timeline.

### 4. Validate the vertical slice

- [ ] Verify recent activity appears when receipts/history exist.
- [ ] Verify empty history does not make Home feel broken.
- [ ] Record any deeper timeline or analytics ideas outside this ticket.

## Critical Edge Case

The recent-activity preview must stay lightweight and understandable even when receipts are sparse or unevenly distributed across surfaces.

## Validation

Show useful recent activity in Home and preserve honest empty-state behavior when there is none.

## Handoff Rule

If the preview starts wanting full timeline behavior, move that work into receipts-focused tickets instead of stretching `P0-102D`.
