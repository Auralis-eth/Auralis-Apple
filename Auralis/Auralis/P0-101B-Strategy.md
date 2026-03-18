# P0-101B Strategy: Global Chrome UI (always visible OS chrome)

## Status

Ready now

## Ticket

Implement the always-visible OS chrome header across primary surfaces, including account switcher, mode badge, freshness indicator, search entry, and context inspector entry.

## Dependencies

P0-101A, P0-201

## Strategy

- Build the chrome shell now.
- Present the mode badge as fixed `Observe` in the first pass.
- Do not invent the final mode-state system inside the chrome layer.
- Keep account, freshness, search, and inspector seams explicit.

## Key Risk

Handle long ENS or nickname truncation, address fallback, compact multi-chain display, and stale or offline freshness states without collapsing the header.

## Definition Of Done

- The chrome is visible across the intended primary surfaces.
- The mode badge is visibly fixed to Observe.
- Account switching, search entry, and freshness display integrate cleanly with the existing shell.

## Validation Target

Verify chrome appears on Home, Music, Tokens, Details, and Receipts; account switching updates scope; mode badge stays Observe; search opens from every surface; freshness updates after refresh.
