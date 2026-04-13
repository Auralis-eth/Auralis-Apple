# P0-301 Tickets And Session Handoff

## Summary

Create the injected, read-only provider interface for chain-aware balance and metadata fetches with centralized RPC configuration.

## Ticket Status

Completed for the current read-only provider slice.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum injected provider slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record the remaining downstream blockers explicitly.

## Critical Edge Case

Handle rate limits, slow responses, unexpected payload shapes, and future provider swapping without leaking direct calls into UI.

## Validation

Fetch native balance on a known chain, surface structured failures, enforce use through Context Service, and reflect provider config changes on restart or refresh.

## Handoff Rule

Do not build throwaway scaffolding. It is acceptable to land injectable provider seams and centralized config now, but any missing context-service ownership, freshness behavior, or token-surface consumers must be recorded as deferred follow-on work.

## Completion Summary

- centralized read-only provider configuration behind one shared resolver for Alchemy-backed endpoints
- routed NFT inventory fetching through an injected provider factory instead of inline concrete construction
- kept gas pricing behind a provider protocol and aligned the live path to the shared configuration resolver
- introduced a shared read-only provider factory in the shell service hub so the app has one consistent place to construct provider-backed reads
- threaded native balance reads through `ContextService`, allowing the shell-facing context snapshot and inspector to surface provider-backed balance data

## Remaining Notes

This ticket is complete for the current Phase 0 read-only provider slice, but some follow-on work remains intentionally deferred:

- ERC-20 balance and token-metadata coverage for later token surfaces
- freshness-policy alignment across provider-backed reads
- stricter boundary enforcement in `P0-701B`

Validation completed in this pass:

- project build succeeded after the provider-seam integration
- a fresh `BuildProject` run succeeded again during the closeout pass after the broader P0 and ERC-20 surface updates
- live Xcode diagnostics returned no issues for the active provider-layer source touched in this pass
- `ProviderAbstractionTests` now passes end to end, covering the intended provider validation slice including endpoint construction, token balances, holdings enrichment, pagination, and retry behavior
