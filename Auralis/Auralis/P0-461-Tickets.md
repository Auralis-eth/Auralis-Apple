# P0-461 Tickets And Session Handoff

## Summary

Implement the first token holdings list for the active account and chain scope, with native balance minimum support and a clean path to later ERC-20 enrichment.

## Ticket Status

Startable.

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

- [ ] Show native balance for the active scope.
- [ ] Add the first row model and list layout for holdings.
- [ ] Keep the row contract stable enough for later ERC-20 enrichment.
- [ ] Preserve honest empty/loading/error states instead of hiding missing data.

### 3. Cover required edge cases

- [ ] Native-only holdings lists remain usable.
- [ ] Missing token metadata does not break row rendering.
- [ ] Failed refresh leaves readable cached or previously known state when possible.
- [ ] Scope changes do not leak holdings across account or chain boundaries.

### 4. Validate the vertical slice

- [ ] Verify native balance appears for the active scope.
- [ ] Verify the holdings surface remains usable with no ERC-20 data.
- [ ] Verify cached or stale state is understandable after refresh failure.
- [ ] Record follow-on work for token detail and enrichment instead of absorbing it here.

## Critical Edge Case

Handle native-only lists, missing token metadata, and stale cached balances after fetch failure without losing a usable holdings surface.

## Validation

Display native balance, preserve understandable cached state on failure, and keep the list contract stable for later enrichment.

## Handoff Rule

If richer ERC-20 or token-detail behavior is still missing when work starts, do not collapse those later tickets into `P0-461`.
