# P0-102A Strategy: Home layout v0 (OS dashboard)

## Status

Partially blocked

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
