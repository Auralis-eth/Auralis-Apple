# P0-462 Tickets And Session Handoff

## Summary

Implement the token detail screen that deepens the holdings list into a real per-token destination.

## Ticket Status

Completed for the current slice.

## Execution Checklist

### 1. Confirm the holdings-to-detail contract

- [x] Re-read `P0-462-Strategy.md` and `P0-462-Dependency-Note.md`.
- [x] Confirm which row types from `P0-461` should open token detail.
- [x] Confirm the minimum metadata contract for native and token rows.

Step 1 notes:

- `P0-461` already established a stable holdings-row contract in `TokenHoldingRowModel`, so `P0-462` is no longer practically blocked for the first slice.
- The mounted ERC-20 surface already has a real detail route seam: `ERC20TokensRootView` opens detail through `router.showERC20Token(...)`, and the tab already mounts `ERC20TokenDetailView` behind `ERC20TokenRoute`.
- The current row-opening rule is explicit in code: only rows with `kind == .erc20` and a non-empty `contractAddress` open detail today; native rows remain list-only unless this ticket intentionally broadens the contract.
- The minimum metadata contract already available from `TokenHolding` and `TokenHoldingRowModel` is enough for a first detail screen:
  - native vs ERC-20 kind
  - display name
  - symbol when present
  - amount display
  - chain scope
  - contract address when present
  - placeholder/sparse metadata flag
  - last updated time
- Product implication for step 2: the first token detail screen should be built on the existing `ERC20TokenRoute` plus scoped `TokenHolding` lookup, and it should stay honest when symbol/name metadata is sparse rather than assuming enrichment already exists.

### 2. Implement the first token detail screen

- [x] Add the route and screen shell for token detail.
- [x] Render the minimum token identity, balance, and scope information.
- [x] Preserve honest partial-data behavior.

Step 2 notes:

- The first token detail screen now uses the existing mounted `ERC20TokenRoute` seam rather than introducing a second routing contract.
- `ERC20TokenDetailView` now resolves the scoped local `TokenHolding` for the active account, chain, and contract address, then renders a real detail screen instead of the previous placeholder list.
- The first-slice screen shows the current token name, symbol, balance display, chain scope, contract address, and update timestamp when available.
- Partial-data behavior is explicit:
  - missing local holding falls back to route-level identity with a clear status message
  - placeholder metadata stays understandable instead of pretending enrichment exists
  - the screen does not assume pricing, history, or fully enriched ERC-20 metadata

### 3. Cover required edge cases

- [x] Native-only tokens remain understandable.
- [x] Missing symbol/name/logo metadata does not break the screen.
- [x] Later enriched fields can attach without redesigning the screen.

Step 3 notes:

- Edge-case coverage now explicitly includes the native-style fallback path the first token-detail contract supports, even though native rows still do not open this route from the list by default.
- Sparse metadata remains understandable through presentation fallbacks for:
  - missing local holding
  - placeholder token metadata
  - missing symbol/name enrichment
- The presentation contract stays open for later enrichment because the screen is already split into stable identity and balance sections instead of hard-coding assumptions about pricing, charts, or logos.

### 4. Validate the vertical slice

- [x] Verify token detail opens from supported holdings rows.
- [x] Verify sparse metadata remains understandable.
- [x] Record any later pricing/history additions outside this ticket.

Step 4 notes:

- `Auralis` builds successfully with the first token-detail screen and edge-case coverage in place.
- Focused tests passed for:
  - `AppRouterTests/erc20RouteFlow()`
  - `ERC20TokenDetailPresentationTests/presentationUsesHoldingMetadata()`
  - `ERC20TokenDetailPresentationTests/presentationDegradesCleanlyForSparseMetadata()`
  - `ERC20TokenDetailPresentationTests/presentationSupportsMissingHolding()`
  - `ERC20TokenDetailPresentationTests/presentationSupportsNativeStyleFallback()`
  - `ERC20TokenDetailPresentationTests/presentationAcceptsLaterEnrichmentWithoutContractChange()`
- Later enrichments remain outside this ticket:
  - price and valuation data
  - transfer/history views
  - charts and market data
  - token logos or provider-enriched branding beyond the current local holdings contract

## Critical Edge Case

The token detail screen must remain useful even when token metadata is incomplete or only a native-balance row exists.

## Validation

Open token detail from the holdings list and keep the screen stable across native-only and sparse-metadata cases.

## Handoff Rule

If the holdings-row contract is still moving, keep this ticket at the route/screen-shell level and avoid premature detail-model lock-in.
