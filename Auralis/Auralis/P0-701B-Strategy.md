# P0-701B Strategy: Layered Module Boundaries Enforcement Completion

## Status

Blocked

## Ticket

Complete the enforcement side of layered boundaries after the service and policy graph is stable enough to lock down.

## Dependencies

P0-602, P0-701A, P0-402

## Strategy

- Tighten the structure created in `P0-701A`.
- Enforce dependency direction once the real seams exist.
- Validate that UI cannot bypass Context or Services to reach Providers directly.

## Key Risk

If enforcement happens before the service graph stabilizes, the team burns time fighting the architecture instead of shipping the product.

## Definition Of Done

- Dependency direction is enforced strongly enough to catch bypass paths.
- UI cannot directly reach provider code.
- Policy and receipt-related seams fit the enforced structure.

## Validation Target

Use structural review and tests to confirm the intended dependency rules now hold in practice.
