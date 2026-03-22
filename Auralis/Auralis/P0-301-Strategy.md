# P0-301 Strategy: Provider abstraction (read-only)

## Status

In Progress

## Ticket

Create the injected, read-only provider interface for chain-aware balance and metadata fetches with centralized RPC configuration.

## Dependencies

P0-204, P0-501, with early structural guidance from `P0-701A`

## Strategy

- Build the provider seam against explicit chain input.
- Align its shape with `P0-701A` structural scaffolding.
- Leave strict enforcement of dependency direction to `P0-701B`.
- Ship one real injected slice now instead of waiting for the full context service graph.

## Key Risk

Handle rate limits, slow responses, unexpected payload shapes, and future provider swapping without leaking direct calls into UI.

## Current Slice

- Centralized provider endpoint resolution now exists for Alchemy and Infura.
- NFT inventory fetching now goes through an injected provider seam instead of constructing Alchemy inline inside `NFTFetcher`.
- Gas pricing now goes through a provider protocol instead of a hard-coded concrete client in the view model.
- Native balance fetching now has a real provider implementation, but it is not yet consumed by a service or UI surface.

## Definition Of Done

- The provider seam is injectable and chain-aware.
- Its ownership fits the early structure-first rules from `P0-701A`.
- Later enforcement in `P0-701B` can lock the boundary down without redesigning the seam.

## Validation Target

Fetch native balance on a known chain, surface structured failures, and confirm the provider shape is suitable for service-only use.

## Remaining Work

- Move native balance reads behind the future context/service layer in `P0-402`.
- Add ERC-20 balance and token metadata coverage when the token surfaces become real consumers.
- Fold provider freshness into the cache/freshness contract from `P0-302`.
