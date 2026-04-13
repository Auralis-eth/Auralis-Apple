# P0-801 Strategy: Canceled

## Status

Canceled

## Decision

`P0-801` is no longer an active Phase 0 ticket.

The earlier plan proposed a deterministic bundled demo dataset plus a dedicated offline-mode product behavior. That approach was rejected because it would introduce a parallel truth source across Home, Newsfeed, NFT Tokens, ERC-20 Tokens, Music, Receipts, and Gas without a strong enough product need.

## What We Kept Instead

- guest passes remain as a lightweight onboarding path to curated public wallets
- real account and guest-pass sessions still use the normal shell and live/cached data seams
- SwiftData-backed local persistence remains the default offline story for already-fetched content
- provider failures and degraded states should stay explicit in the shell instead of being reframed as a separate fake mode

## What We Are Not Doing

- no bundled demo dataset
- no special non-production demo-data mode
- no cross-surface demo/offline second source of truth
- no ticket work to make every tab render fixture-backed fake content

## Practical Rule

If the app is offline, it should show whatever real local state SwiftData already has and remain honest about missing provider-backed refreshes. If a future product requirement wants a deliberate scripted demo experience, that must come back as a new ticket with a concrete consumer.
