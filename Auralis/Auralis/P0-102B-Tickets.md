# P0-102B Tickets And Session Handoff

## Summary

Deepen the active account summary card on Home so it acts like a real identity and scope surface.

## Ticket Status

Completed for the current slice.

## Execution Checklist

### 1. Confirm card scope and inputs

- [x] Re-read `P0-102B-Strategy.md` and `P0-102B-Dependency-Note.md`.
- [x] Confirm which account, chain, and context fields belong on the first card.
- [x] Confirm which existing temporary visuals are acceptable to preserve.

Scope notes:

- The current summary card seam is `ProfileCardView` inside the Home identity section. It already owns avatar display/generation, ENS reverse lookup, current address display, and account-switcher entry.
- The first strengthened card should stay inside that existing slot rather than inventing a second identity surface elsewhere in Home.
- Trustworthy first-slice account fields already available from owned state are:
  - active account display name (`currentAccount?.name`)
  - active address (`currentAccount?.address` / `currentAddress`)
  - current chain scope (`currentAccount?.currentChain` or the bound `currentChain`)
  - account activity recency (`currentAccount?.mostRecentActivityAt`)
  - tracked NFT count (`currentAccount?.trackedNFTCount`)
- Optional context-like fields that are safe only if passed in explicitly and degraded honestly are things such as native balance or broader shell summary values; they should not be re-fetched or re-invented locally inside `ProfileCardView`.
- The first card should prefer a small number of trustworthy fields over speculative or laggy data. Chain scope, address, name, and local tracked count are better first additions than richer portfolio statistics.
- Existing temporary visuals that are acceptable to preserve for this slice are:
  - the generated/fallback avatar flow
  - ENS display when available
  - the current scenic/glass card treatment
  - the existing account switcher affordance
- Existing temporary visuals that should not expand this ticket into a broader feature are:
  - turning the avatar area into profile editing
  - adding full settings/account-management UI
  - treating QR affordances as a full auth-management workflow

### 2. Implement the strengthened summary card

- [x] Add the real identity/scope fields to the Home summary card.
- [x] Keep the card readable and intentionally scoped.
- [x] Preserve existing Home visual language.

Implementation notes:

- Strengthened `ProfileCardView` in the existing Home identity slot instead of adding a parallel summary surface.
- The card now shows a real account title, scoped address, chain scope, scoped NFT count, and last-activity summary while preserving ENS display, avatar generation/fallback, and the existing account-switcher entry.
- The summary contract is now explicit in `HomeTabLogic.accountSummaryPresentation(...)` so the card fields remain grounded in already-owned shell/account state.
- Richer portfolio/balance fields were intentionally left out of this slice to keep the card trustworthy when optional context values lag or are absent.

### 3. Cover required edge cases

- [x] Missing optional context values degrade cleanly.
- [x] Chain/account switches update the card correctly.
- [x] The card remains useful even when richer balances or activity data are absent.

Edge-case coverage notes:

- Moved the card field derivation behind a small `HomeAccountSummaryPresentation` contract so the risky cases can be unit-tested without depending on view rendering.
- Covered the empty-optional path: missing account name falls back to `Active Account`, zero scoped NFTs renders an honest local-state label, and absent activity data suppresses the last-activity line instead of inventing placeholder text.
- Covered scope churn: changing account identity or chain scope produces a different summary payload so the card can track real shell changes without stale text leaking across contexts.
- Covered sparse richer-data conditions: the card still presents a useful identity summary when balances or richer activity context are unavailable.

### 4. Validate the vertical slice

- [x] Verify the card reflects the active account and scope.
- [x] Verify the card stays visually coherent in sparse-data conditions.
- [x] Record any profile-management or settings follow-ons outside this ticket.

Validation notes:

- `Auralis` builds successfully with the strengthened summary-card slice in place.
- The full `HomeTabLogicTests` suite passed for this Home vertical slice, including sparse-state and summary-card coverage:
  - `logoutPlanClearsSessionWithoutDeletingRoster()`
  - `sparseDataStateUsesScopedLocalSignals()`
  - `sparseStatePresentationDefersToLoadingAndFailure()`
  - `sparseStatePresentationUsesRealNextActions()`
  - `sparseStatePresentationClearsOnceDashboardHasData()`
  - `accountSummaryPresentationUsesOwnedFields()`
  - `accountSummaryPresentationDegradesCleanly()`
  - `accountSummaryPresentationTracksAccountAndChainSwitches()`
  - `accountSummaryPresentationRemainsUsefulWithoutActivity()`
- Within the no-UI-tests constraint, visual coherence is validated indirectly by keeping the strengthened card inside the existing `ProfileCardView` layout and mounted Home shell rather than introducing an alternate sparse-state card implementation for identity.
- Follow-ons explicitly kept out of `P0-102B`:
  - richer profile-management flows
  - settings/edit-account behavior
  - speculative portfolio or balance summary fields

## Critical Edge Case

The card must stay trustworthy when optional context fields are absent or lag behind richer future integrations.

## Validation

Show a stronger active account summary using real shell/account data without overreaching into profile-management work.

## Handoff Rule

If the card wants richer editing or management behavior, split that into later tickets instead of stretching `P0-102B`.
