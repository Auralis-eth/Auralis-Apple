# P0-204 Tickets And Session Handoff

## Summary

Add per-account chain scope settings that drive Context Builder and downstream library surfaces.

## Execution Order

1. Re-read the dependencies and confirm which ones are already complete.
2. Implement the minimum vertical slice that proves the ticket is real.
3. Cover the stated edge cases before expanding scope.
4. Run the ticket-specific validation path and record any blockers.

## Critical Edge Case

Prevent empty chain scope, handle out-of-scope detail screens gracefully, and design a list that can grow later.

## Validation

Persist chain scope per account, trigger context rebuild and receipts on scope change, and verify library surfaces respect the selected scope.

## Completion Summary

- Unified persisted per-account chain scope with the live shell `currentChain`
- updated shell restore and selection flows so the active account owns the visible chain scope
- added receipt-backed preferred-chain and current-chain change events
- suppressed no-op chain reselections before persistence, receipt writes, or refresh hooks run
- wired current-chain changes to a single NFT refresh callback for the active scope

## Handoff Rule

Treat this ticket as complete for the current Phase 0 shell baseline. Future work should extend it through `P0-401` / `P0-402`, not reintroduce parallel chain-state ownership.
