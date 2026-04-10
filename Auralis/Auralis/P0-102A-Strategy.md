# P0-102A Strategy: Home layout v0 (OS dashboard)

## Status

Complete

## Ticket

Build the OS-level Home dashboard with active account summary, module tiles, recent activity preview, and quick links.

## Dependencies

P0-101A, P0-101E, P0-201, P0-402, P0-503

## Strategy

- Start the Home layout as soon as the shell and primitives are ready.
- Allow placeholder-backed module tiles and previews to break downstream dependency cycles.
- Keep the dashboard navigable even when context and receipts are still partial.

## Key Risk

Show onboarding when no account exists, keep the dashboard navigable when context is unavailable, and handle empty or placeholder-backed activity and module data cleanly.

## Definition Of Done

- The Home dashboard exists as an OS-level surface.
- Placeholder-backed modules can later be replaced by real module data without rewriting the layout.
- The ticket integrates cleanly with real context and receipts once those dependencies land.

## Validation Target

Render with demo or offline data, render with real cached context, verify tile routing, and open receipt details from recent activity.

## Current Slice

- `HomeTabView` now reads as a structured dashboard instead of a loose stack of cards and utility actions
- the scenic background and glass-card visual language remain intact by product choice
- Home now has explicit sections for identity, modules, recent activity, quick links, and temporary profile-studio controls
- recent activity now shows a scoped local receipts preview and routes into receipt detail
- quick links now provide deliberate navigation into News, Search, and Receipts without waiting for later Home card tickets

## Remaining Work

`P0-102A` is complete for the current dashboard-shell slice.

Home now has an explicit account-summary section, a dedicated quick-links section, scoped recent activity, and shell-owned pinned shortcuts without reopening later Home follow-on tickets. The downstream Home tickets remain deepen-and-polish work, not missing layout baseline work.
