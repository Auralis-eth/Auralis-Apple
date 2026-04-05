# P0-102D Tickets And Session Handoff

## Summary

Deepen the Home recent-activity preview so it provides a real shell summary of recent actions and system events.

## Ticket Status

Completed for the current slice.

## Execution Checklist

### 1. Confirm the preview source

- [x] Re-read `P0-102D-Strategy.md` and `P0-102D-Dependency-Note.md`.
- [x] Confirm which receipt/activity sources should feed the first preview.
- [x] Confirm which deeper route the preview should open into.

Preview source notes:

- The seam is the existing `recentActivitySection` in `HomeTabView`, which already renders a scoped recent-activity card in Home.
- The first preview should stay backed by local `StoredReceipt` rows only, using the existing `ReceiptTimelineRecord` mapping and `ReceiptTimelineScope` filtering already present in Home.
- The current Home path is:
  - query `StoredReceipt` rows sorted by recency
  - map them into `ReceiptTimelineRecord`
  - filter them by the active account and chain scope with `matches(receiptScope)`
  - preview only the first few rows in Home
- The deeper routes are already defined and should remain the first-pass contract:
  - tapping a preview row opens receipt detail via `router.showReceipt(id:)`
  - tapping the section trailing action opens the broader receipts surface via `router.showReceipts()`
- The first slice should not invent a second activity source, analytics feed, or special Home-only event model. The receipts foundation is already the trustworthy source of recent shell/system activity for this preview.

### 2. Implement the recent-activity preview

- [x] Render a lightweight recent-activity list or strip in Home.
- [x] Keep the preview shorter and simpler than the full receipts surface.
- [x] Route into richer history/detail when selected.

Implementation notes:

- The Home recent-activity section now derives a dedicated lightweight preview contract from scoped receipt records instead of rendering raw receipt rows directly.
- `HomeTabLogic.recentActivityPreviewItems(...)` now compresses receipt data into Home-sized rows with:
  - a clear title
  - a lighter detail line
  - a scope/actor context line
  - status emphasis
- The preview is now intentionally shorter than the full receipts surface by limiting Home to the first 3 preview rows even though the underlying scoped recent-activity source can still observe a slightly broader local receipt set.
- The deeper routing contract remains unchanged:
  - tapping a preview row opens receipt detail
  - the section trailing action opens the receipts surface
- The Home preview now stays visually lighter-weight than the receipts timeline while still using the same trustworthy receipt foundation.

### 3. Cover required edge cases

- [x] Empty activity history is shown honestly.
- [x] Sparse or partial receipt data does not break the section.
- [x] Preview rows remain understandable without requiring users to open the full timeline.

Edge-case coverage notes:

- `HomeTabLogic.recentActivityPreviewItems(...)` now carries the Home preview contract so empty-history and partial-data behavior can be unit-tested without rendering the full view.
- Empty-history coverage now proves that Home returns an empty preview set rather than inventing placeholder rows.
- Partial-data coverage now proves that readable preview rows still exist when summary text is missing, trigger text is sparse, or both collapse down to a scope-based fallback.
- Readability coverage now proves the Home preview remains intentionally shorter than the receipts timeline while still producing understandable titles, context, and status cues.

### 4. Validate the vertical slice

- [x] Verify recent activity appears when receipts/history exist.
- [x] Verify empty history does not make Home feel broken.
- [x] Record any deeper timeline or analytics ideas outside this ticket.

Validation notes:

- `Auralis` builds successfully with the recent-activity preview slice in place.
- The full `HomeTabLogicTests` suite passed for the current Home slice, including sparse-state, summary-card, launcher, and recent-activity coverage.
- For the recent-activity preview specifically, the unit-test validation now proves:
  - Home keeps the preview shorter than the full receipts surface
  - empty scoped history produces no fake preview rows
  - sparse or partial receipt strings still produce understandable preview text
  - the preview contract remains lightweight and Home-oriented rather than timeline-dense
- Follow-ons explicitly left outside `P0-102D`:
  - deeper receipts timeline behaviors
  - analytics or trend-summary layers
  - broader receipts-surface redesign beyond the Home preview contract

## Critical Edge Case

The recent-activity preview must stay lightweight and understandable even when receipts are sparse or unevenly distributed across surfaces.

## Validation

Show useful recent activity in Home and preserve honest empty-state behavior when there is none.

## Handoff Rule

If the preview starts wanting full timeline behavior, move that work into receipts-focused tickets instead of stretching `P0-102D`.
