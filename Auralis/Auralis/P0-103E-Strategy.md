# P0-103E Strategy: No-results + safety behavior

## Status

Blocked

## Ticket

Implement safe no-results search UX with clear next steps, explorer fallback, watch-only account creation, and strict Observe-only boundaries.

## Dependencies

P0-601, P0-602, P0-502, with `P0-101D` as a recommended parallel foundation

## Strategy

- Do not wait on `P0-101D` to define the underlying safety rules.
- Use `P0-101D` to shape the final empty-state language.
- Keep Observe-only and no-execute constraints as the real gate.

## Key Risk

Suggestions must remain safe and non-misleading, and no search path should imply execution capability.

## Definition Of Done

- No-results flows are safe and clearly explained.
- Observe-only constraints are enforced.
- The UI can align with `P0-101D` patterns without changing the safety model.

## Validation Target

Verify no-results suggestions, watch-only add-account flow, explorer open receipts, and absence of any execute path from search.
