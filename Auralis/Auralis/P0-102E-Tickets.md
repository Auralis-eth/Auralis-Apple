# P0-102E Tickets And Session Handoff

## Summary

Implement the Home empty and first-run state so the dashboard remains intentional when there is little or no useful local data.

## Ticket Status

Startable.

## Execution Checklist

### 1. Confirm the sparse-data triggers

- [x] Re-read `P0-102E-Strategy.md` and `P0-102E-Dependency-Note.md`.
- [x] Confirm which signals define first-run vs sparse-data vs normal Home.
- [x] Confirm which existing routes should be offered as next steps from the empty state.

Scope notes:

- True no-account first run is still owned by `GatewayView`; `HomeTabView` only mounts once `MainAuraView` has a non-nil `currentAccount`.
- Inside Home, the relevant sparse-data signals already exist locally: scoped NFT count (`scopedNFTs`), scoped recent activity (`recentActivity` from receipts), and the music subset count (`musicNFTCount`).
- For `P0-102E`, treat the Home empty state as an active-account-but-low-local-data condition, not as a replacement for onboarding, loading, or provider-failure screens.
- First-run Home state: active account is present, Home is not loading, there is no provider-failure overlay in control, and both scoped NFTs and scoped receipt activity are empty.
- Sparse-data Home state: active account is present and one or more of the Home sections is empty, but the scope is not fully blank; this should still use the mounted Home shell instead of falling back to a global empty screen.
- Normal Home state: scoped data exists for one or more mounted sections and the current dashboard layout should remain primary.
- The existing real next-step routes already available from Home are: account switching via the profile card, News (`router.selectedTab = .news`), Search (`router.showSearch()`), Receipts (`router.showReceipts()`), Music (`router.showMusicLibrary()`), and NFT Tokens (`router.showNFTTokens()`).
- There is no dedicated Home refresh action wired into `HomeTabView` today, so `P0-102E` should not pretend a refresh CTA exists unless that action is explicitly added as part of the ticket.

### 2. Implement the first-run Home state

- [x] Add the empty/first-run treatment inside the existing Home shell.
- [x] Provide clear next actions such as account setup, refresh, search, or explore.
- [x] Keep the scenic/glass language aligned with the current Home design.

Implementation notes:

- Added an explicit Home sparse-data state contract in `HomeTabLogic` with `firstRun`, `sparse`, and `normal` outcomes driven by scoped NFT and scoped receipt counts.
- Added an in-shell `AuraEmptyState` treatment near the top of `HomeTabView` instead of replacing the mounted dashboard structure.
- First-run and sparse states now offer only real next-step actions already available from Home today: Search, News, and account switching.
- The existing scenic/glass Home language stays intact because the new state is rendered as another Home surface card rather than a separate full-screen design.

### 3. Cover required edge cases

- [x] Home distinguishes empty from loading or provider failure.
- [x] Sparse state remains usable without receipts or recent activity.
- [x] Route actions from the empty state land on real product surfaces.

Edge-case notes:

- Sparse-state presentation is now explicit and suppresses itself during loading or failure conditions instead of competing with those states.
- First-run and sparse Home remain usable when receipts or recent activity are missing because the mounted Home shell still shows identity, modules, quick links, and the sparse guidance card.
- Sparse-state actions are constrained to real existing routes only: Search, News, and account switching.
- Provider-failure suppression is represented in the Home sparse-state contract even though the mounted Home shell does not currently own a dedicated provider-failure surface of its own.

### 4. Validate the vertical slice

- [x] Verify Home is understandable on first run.
- [x] Verify the state clears cleanly once data exists.
- [x] Record any later copy or visual deepening as follow-on work instead of folding it into this ticket.

Automated validation completed:

- Unit tests cover first-run vs sparse vs normal trigger detection.
- Unit tests cover suppression during loading or failure conditions.
- Unit tests cover action mapping to real existing routes only.
- Unit tests cover the first-run presentation contract and verify the sparse-state presentation clears once local data exists.
- The `Auralis` scheme builds successfully with the Home sparse-state implementation.

Follow-on work explicitly deferred:

- Any copy polish beyond the current first-run/sparse messaging.
- Any visual deepening or richer Home empty-state art direction beyond the current scenic/glass card treatment.
- Any dedicated Home provider-failure surface, since provider-failure ownership still lives outside this ticket's scoped sparse-data slice.

## Critical Edge Case

Do not confuse empty or first-run state with loading, error, or broken-shell state.

## Validation

Show a coherent Home experience for first-run and sparse-data conditions, with real next-step routing.

## Handoff Rule

If later Home sections are still incomplete, keep this ticket focused on the empty-state experience rather than filling the dashboard with throwaway placeholders.
