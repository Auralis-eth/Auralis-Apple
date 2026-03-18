# P0-301 Strategy: Provider abstraction (read-only)

## Status

Blocked

## Ticket

Create the injected, read-only provider interface for chain-aware balance and metadata fetches with centralized RPC configuration.

## Dependencies

P0-204, P0-501, with early structural guidance from `P0-701A`

## Strategy

- Build the provider seam against explicit chain input.
- Align its shape with `P0-701A` structural scaffolding.
- Leave strict enforcement of dependency direction to `P0-701B`.

## Key Risk

Handle rate limits, slow responses, unexpected payload shapes, and future provider swapping without leaking direct calls into UI.

## Definition Of Done

- The provider seam is injectable and chain-aware.
- Its ownership fits the early structure-first rules from `P0-701A`.
- Later enforcement in `P0-701B` can lock the boundary down without redesigning the seam.

## Validation Target

Fetch native balance on a known chain, surface structured failures, and confirm the provider shape is suitable for service-only use.
