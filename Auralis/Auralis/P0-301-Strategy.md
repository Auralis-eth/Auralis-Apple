# P0-301 Strategy: Provider abstraction (read-only)

## Status

Completed for the current Phase 0 read-only provider slice

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

- Centralized provider endpoint resolution now exists for the shared Alchemy-backed provider seam.
- NFT inventory fetching now goes through an injected provider seam instead of constructing Alchemy inline inside `NFTFetcher`.
- Gas pricing now goes through a provider protocol instead of a hard-coded concrete client in the view model.
- The shell service hub now owns the shared read-only provider factory for inventory, gas, and native balance reads.
- Native balance fetching now has a real provider implementation and is consumed by `ContextService`, so the shell-facing context contract can surface provider-backed balance data.

## Definition Of Done

- The provider seam is injectable and chain-aware.
- Its ownership fits the early structure-first rules from `P0-701A`.
- Later enforcement in `P0-701B` can lock the boundary down without redesigning the seam.

## Validation Target

Fetch native balance on a known chain, surface structured failures, and confirm the provider shape is suitable for service-only use.

## Remaining Work

- Add ERC-20 balance and token metadata coverage when the token surfaces become real consumers.
- Fold provider freshness into the cache/freshness contract from `P0-302`.
- Leave stronger boundary enforcement and anti-bypass cleanup to `P0-701B`.
