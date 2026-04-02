# P0-102D Dependency Note

## Status

Startable

## Dependency Read

- `P0-102A` already created the recent-activity slot on Home.
- `P0-403` and the current receipts inspector slice provide enough receipt-aware grounding for the preview.
- `P0-501` and `P0-502` already provide the receipt foundation and active logging baseline.

## Safe First Slice

- Use recent receipts or recent shell activity as the preview source.
- Keep the preview intentionally compressed and route into deeper history surfaces when needed.
- Preserve honest empty-state behavior when there is no recent activity.

## Rule For Planning

Do not turn this preview into a full receipt timeline replacement or into an analytics dashboard.
