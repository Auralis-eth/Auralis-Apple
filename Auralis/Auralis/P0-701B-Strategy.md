# P0-701B Strategy: Layered boundaries enforcement completion

## Status

Partially blocked

## Ticket

Complete the layered-boundaries enforcement pass so shell/service/view ownership rules are no longer just conventions.

## Dependencies

- `P0-701A`
- `P0-602`
- active feature-slice adoption

## Strategy

- Build on the structural scaffolding from `P0-701A`.
- Convert boundary rules from guidance into enforceable usage patterns.
- Tackle the highest-value bypasses first instead of forcing one giant purity rewrite.

## Key Risk

Avoid broad enforcement work before the active feature slices have settled enough to show where the real seams belong.

## Definition Of Done

- Major shell/service boundary shortcuts are removed or explicitly gated.
- The architecture rules are enforceable in practice, not just documented.
- Later smoke tests can verify bypass paths more confidently.

## Validation Target

Reduce or remove known shortcut paths and make boundary ownership easier to verify in code review and smoke tests.
