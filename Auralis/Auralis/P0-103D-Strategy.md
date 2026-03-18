# P0-103D Strategy: Search results UI (grouped + provenance-labeled)

## Status

Blocked

## Ticket

Render grouped search results with provenance badges, safe copy actions, and navigation into the correct detail surfaces.

## Dependencies

P0-103C, P0-101A, P0-501

## Strategy

- Keep the implementation narrow and phase-correct.
- Build only the minimum seams needed by downstream tickets.
- Make UI and state ownership explicit instead of hiding behavior in helpers.
- Validate the named edge cases before broadening scope.

## Key Risk

Deduplicate repeated entities, truncate long names safely, and keep large result sets bounded with clear affordances.

## Definition Of Done

- The ticket outcome is visible in product behavior.
- The ticket integrates cleanly with its immediate dependencies.
- The stated test plan can be run without inventing extra architecture.

## Validation Target

Verify mixed grouped results, navigation for each result type, copy actions with receipts, and provenance labels that match the real source.
