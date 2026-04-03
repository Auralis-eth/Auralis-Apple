# P0-461 Tickets And Session Handoff

## Summary

Implement the first token holdings list for the active account and chain scope, with native balance minimum support and a clean path to later ERC-20 enrichment.

## Ticket Status

Implemented for the native-balance-first slice. Automated validation is complete, manual UI QA remains open, and provider-backed token holdings retrieval is deferred follow-on work.

## Execution Checklist

### 1. Confirm scope and data seams

- [x] Re-read `P0-461-Strategy.md` and `P0-461-Dependency-Note.md`.
- [x] Confirm the active shell route that should host the holdings list.
- [x] Confirm the native-balance provider seam and any placeholder/local-backed token source allowed for the first slice.
- [x] Confirm the receipt/freshness path that later refresh actions should extend.

Scope notes:

- Host the first holdings list in `ERC20TokensRootView` inside `MainTabView`. The tab and token-detail routing already exist; only the placeholder root surface is missing real holdings content.
- Use the existing read-only provider seam for native balance: `ReadOnlyProviderFactory.makeNativeBalanceProvider()` -> `NativeBalanceProviding` -> `ContextService.resolveNativeBalance(...)`.
- Token holdings should be persisted with SwiftData rather than treated as view-only transient state. The v0 list can start with native balance plus placeholder/local-backed rows, but the storage direction is durable SwiftData-backed holdings data.
- For the first slice, strategy explicitly allows placeholder, local, or cached ERC-20 rows while keeping the row contract stable for later provider-backed enrichment.
- Extend the current scope-aware freshness and receipt path rather than inventing a parallel one: `MainTabView` already calls `contextService.refresh(...)` with `ReceiptEventLogger`, and receipt filtering is already keyed by active account and chain scope.

### 2. Implement the minimum holdings list

- [x] Show native balance for the active scope.
- [x] Add the first row model and list layout for holdings.
- [x] Keep the row contract stable enough for later ERC-20 enrichment.
- [x] Preserve honest empty/loading/error states instead of hiding missing data.

Implementation notes:

- Added a SwiftData-backed `TokenHolding` model scoped by normalized account address and chain.
- Added `TokenHoldingsStore` to upsert the native holding from the shell context snapshot without creating a second provider path.
- Replaced the `ERC20TokensRootView` placeholder with a real holdings list that reads persisted rows for the active scope.
- The list currently persists and renders the native holding row first, keeps a stable row model for later ERC-20 rows, and keeps cached rows visible when a later refresh does not return a fresh native balance value.

### 3. Cover required edge cases

- [x] Native-only holdings lists remain usable.
- [x] Missing token metadata does not break row rendering.
- [x] Failed refresh leaves readable cached or previously known state when possible.
- [x] Scope changes do not leak holdings across account or chain boundaries.

Edge-case notes:

- Native-only holdings are now the default supported case: the ERC-20 tab renders a persisted native row without requiring any ERC-20 enrichment to exist first.
- Missing ERC-20 metadata is covered by the stable row contract: placeholder rows can render without symbol or contract metadata and do not attempt broken detail navigation.
- Failed refreshes preserve readable cached state when a previously persisted holding already exists because the screen reads SwiftData-backed rows and only upserts when a fresh native balance is available.
- Scope isolation is enforced by normalized account address plus chain scoping in `TokenHolding` persistence and in the holdings query used by `ERC20TokensRootView`.

### 4. Validate the vertical slice

- [ ] Verify native balance appears for the active scope.
- [ ] Verify the holdings surface remains usable with no ERC-20 data.
- [ ] Verify cached or stale state is understandable after refresh failure.
- [x] Record follow-on work for token detail and enrichment instead of absorbing it here.

Automated validation completed:

- Build succeeded for the `Auralis` scheme after the holdings implementation landed.
- Focused tests passed for native persistence, same-scope upsert behavior, account-and-chain scope isolation, and placeholder metadata row rendering.

Manual QA still required:

- Confirm the ERC-20 tab shows the native balance row for a live active scope in the running app.
- Confirm the native-only surface reads clearly with no ERC-20 rows present.
- Confirm the degraded/banner messaging is understandable after a live provider failure while cached holdings remain visible.

Follow-on work explicitly deferred:

- Add a provider-backed API call to fetch token holdings for an account so ERC-20 rows can be populated from live account inventory.
- Persist that provider-backed token inventory into the existing `TokenHolding` SwiftData model instead of introducing a second token cache shape.
- Keep richer token detail and enrichment behavior outside `P0-461`.

## Critical Edge Case

Handle native-only lists, missing token metadata, and stale cached balances after fetch failure without losing a usable holdings surface.

## Validation

Display native balance, preserve understandable cached state on failure, and keep the list contract stable for later enrichment.

## Handoff Rule

If richer ERC-20 or token-detail behavior is still missing when work starts, do not collapse those later tickets into `P0-461`.
