# P0-102D Strategy: Recent activity preview

## Status

Completed for the current slice

## Ticket

Deepen the Home recent-activity preview so it acts like a real shell summary of what just happened, rather than a generic placeholder strip.

## Dependencies

- `P0-102A`
- `P0-403`
- `P0-501`
- `P0-502` slices

## Strategy

- Reuse the receipts and recent-history groundwork already in the shell.
- Keep the preview lightweight: it should summarize activity, not replace the receipts surface.
- Route into richer receipt or detail views when the user wants more.

## Key Risk

Avoid turning the preview into a noisy event dump or a second copy of the receipts timeline.

## Definition Of Done

- Home shows a useful recent-activity preview.
- Sparse or empty history is handled honestly.
- The preview can route into deeper history/detail surfaces.

## Validation Target

Show recent activity when it exists, stay honest when it does not, and keep the preview clearly lighter-weight than the full receipts experience.
