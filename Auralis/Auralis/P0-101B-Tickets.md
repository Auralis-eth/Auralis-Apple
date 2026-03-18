# P0-101B Tickets And Session Handoff

## Summary

Implement the always-visible OS chrome header across primary surfaces, including account switcher, mode badge, freshness indicator, search entry, and context inspector entry.

## Execution Order

1. Confirm the mount points in the existing shell and routed surfaces.
2. Implement the chrome shell with fixed Observe presentation first.
3. Wire account switching, freshness display, search entry, and context-inspector entry.
4. Cover truncation and stale or offline display edge cases.

## Critical Edge Case

Handle long ENS or nickname truncation, address fallback, compact multi-chain display, and stale or offline freshness states without collapsing the header.

## Validation

Verify chrome appears on Home, Music, Tokens, Details, and Receipts; account switching updates scope; mode badge stays Observe; search opens from every surface; freshness updates after refresh.

## Handoff Rule

If `P0-601` is not done yet, keep the badge visually fixed to Observe and avoid burying mode-state ownership inside the chrome layer.
