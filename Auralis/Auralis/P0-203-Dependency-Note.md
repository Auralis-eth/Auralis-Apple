# P0-203 Dependency Note

## Status

Ready

## Dependencies Reviewed

- P0-201
- P0-301
- P0-302
- P0-502

## Current Decision

The first implementation will use the installed Argent `web3.swift` ENS support behind a provider-agnostic service seam.

This is now considered safe because the upstream account, provider, cache, and receipt seams are present enough to avoid throwaway scaffolding, and the package already includes native ENS forward and reverse lookup support.

## Safe Pre-Work

- Confirm the ENS service contract before wiring the provider implementation.
- Avoid shipping `web3.swift` types or helper APIs into app-facing code.
- Keep all cache, freshness, and receipt semantics backend-agnostic.
- Only do work that lowers the later swap cost to direct Ethereum RPC or a lighter node path.

## Implementation Guardrails

- Treat ENS as Ethereum mainnet identity data regardless of the currently selected app chain.
- Keep `web3.swift` imports at the adapter boundary instead of scattering them through views, models, or shell logic.
- Convert `EthereumAddress` and `EthereumNameServiceError` into Auralis-owned value and error types immediately.
- Require reverse lookup to pass forward verification before it is shown as trusted identity text.
- Prefer injected seams and test doubles over live RPC in most tests.

## Unblock Condition

The upstream dependencies above are complete enough that this ticket can be implemented without inventing temporary state models or disposable UI.
