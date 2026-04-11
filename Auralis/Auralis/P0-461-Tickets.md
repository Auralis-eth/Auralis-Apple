# P0-461 Tickets And Session Handoff

## Summary

Implement the first token holdings list for the active account and chain scope, with native balance minimum support and a clean path to later ERC-20 enrichment.

## Ticket Status

Implemented for the provider-backed holdings slice. Automated validation is complete, manual UI QA remains open, and richer pricing/history enrichment is deferred follow-on work.

## Execution Checklist

### 1. Confirm scope and data seams

- [x] Re-read `P0-461-Strategy.md` and `P0-461-Dependency-Note.md`.
- [x] Confirm the active shell route that should host the holdings list.
- [x] Confirm the native-balance provider seam and the provider-backed ERC-20 source for the completed slice.
- [x] Confirm the receipt/freshness path that later refresh actions should extend.

Scope notes:

- Host the first holdings list in `ERC20TokensRootView` inside `MainTabView`. The tab and token-detail routing already exist; only the placeholder root surface is missing real holdings content.
- Use the existing read-only provider seam for native balance: `ReadOnlyProviderFactory.makeNativeBalanceProvider()` -> `NativeBalanceProviding` -> `ContextService.resolveNativeBalance(...)`.
- Token holdings should be persisted with SwiftData rather than treated as view-only transient state. The v0 list can start with native balance plus placeholder/local-backed rows, but the storage direction is durable SwiftData-backed holdings data.
- The landed slice still keeps the stable row contract, but ERC-20 rows now come from the existing Alchemy-backed provider stack rather than remaining local-only.
- Extend the current scope-aware freshness and receipt path rather than inventing a parallel one: `MainTabView` already calls `contextService.refresh(...)` with `ReceiptEventLogger`, and receipt filtering is already keyed by active account and chain scope.

### 2. Implement the holdings reconciliation slice

- [x] Show native balance for the active scope.
- [x] Add the first row model and list layout for holdings.
- [x] Reconcile provider-backed ERC-20 rows into the scoped SwiftData holdings store.
- [x] Preserve honest empty/loading/error states instead of hiding missing data.

Implementation notes:

- Added a SwiftData-backed `TokenHolding` model scoped by normalized account address and chain.
- Expanded `TokenHoldingsStore` so the same scoped persistence layer can reconcile provider-backed ERC-20 rows and remove stale token rows for the active scope.
- Replaced the `ERC20TokensRootView` placeholder with a real holdings list that reads persisted rows for the active scope.
- Expanded the existing read-only provider configuration with Alchemy Data API support and added a provider-backed token holdings fetcher instead of introducing new networking outside the existing stack.
- The list now persists and renders the native holding row first, reconciles live ERC-20 rows into the same store, and keeps cached rows visible when a later refresh does not return a fresh provider response.

### 3. Cover required edge cases

- [x] Native-only holdings lists remain usable.
- [x] Missing token metadata does not break row rendering.
- [x] Failed refresh leaves readable cached or previously known state when possible.
- [x] Scope changes do not leak holdings across account or chain boundaries.

Edge-case notes:

- Native-only holdings are now the default supported case: the ERC-20 tab renders a persisted native row without requiring any ERC-20 enrichment to exist first.
- Missing ERC-20 metadata is covered by the stable row contract: placeholder rows can render without symbol or contract metadata and do not attempt broken detail navigation.
- Failed refreshes preserve readable cached state when previously persisted holdings already exist because the screen reads SwiftData-backed rows and only reconciles them when a fresh provider response succeeds.
- Scope isolation is enforced by normalized account address plus chain scoping in `TokenHolding` persistence and in the holdings query used by `ERC20TokensRootView`.

### 4. Validate the vertical slice

- [ ] Verify native balance appears for the active scope.
- [ ] Verify the holdings surface remains usable with no ERC-20 data.
- [ ] Verify live ERC-20 rows appear for a wallet with known holdings on a supported chain.
- [ ] Verify cached or stale state is understandable after refresh failure.
- [x] Record follow-on work for token detail and enrichment instead of absorbing it here.

Automated validation completed:

- Build succeeded for the `Auralis` scheme after the provider-backed holdings implementation landed.
- Focused tests passed for native persistence, same-scope upsert behavior, account-and-chain scope isolation, placeholder metadata row rendering, stale ERC-20 row cleanup, and Alchemy token holdings request/decoding.

Manual QA still required:

- Confirm the ERC-20 tab shows the native balance row for a live active scope in the running app.
- Confirm the native-only surface reads clearly with no ERC-20 rows present.
- Confirm known ERC-20 holdings appear for a supported wallet and chain.
- Confirm the degraded/banner messaging is understandable after a live provider failure while cached holdings remain visible.

Follow-on work explicitly deferred:

- Add token valuation, pricing summaries, and richer token identity fields when the detail and Home consumers are ready.
- Keep richer token detail and enrichment behavior outside `P0-461`.

## Critical Edge Case

Handle native-only lists, missing token metadata, and stale cached balances after fetch failure without losing a usable holdings surface.

## Validation

Display native balance, preserve understandable cached state on failure, and keep the list contract stable for later enrichment.

## Handoff Rule

If richer ERC-20 or token-detail behavior is still missing when work starts, do not collapse those later tickets into `P0-461`.
