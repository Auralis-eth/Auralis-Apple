# Phase 4 Remediation Tasks

This is the focused "do now" task list for the current partial Phase 4 work.

Scope decision locked for this pass:

- `P0-101B`: do not add a dedicated freshness indicator to global chrome.
- `P0-302`: freshness remains available through the context sheet and shared freshness state, not a chrome pill.

Practical implication:

- The real work now is not "invent the future."
- The real work now is "finish the slice we already started and integrate it across the app where the current architecture already expects it."

## What Is Not Truly Blocked

Some items that looked blocked are actually unfinished integration work:

- `P0-101C` is still blocked on full inspector behavior, but the freshness/context plumbing underneath it can still be completed now.
- `P0-403` is still blocked as a dedicated ticket, but the current inspector sheet can still absorb more real context data now.
- `P0-203` should still wait on provider/cache maturity.
- The shell-wide rollout of receipts, context usage, and degraded-mode behavior is not future-ticket work. It is current-ticket completion work.

## Active Remediation Set

### `P0-101B` Global Chrome UI

Goal for this pass:

- finish the current chrome contract without introducing a chrome freshness pill

Relevant docs:

- `Auralis/P0-101B-Strategy.md`
- `Auralis/P0-101B-Dependency-Report.md`
- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-Remediation-Checklist.md`

Relevant code:

- `Auralis/Auralis/Aura/GlobalChromeView.swift`
- `Auralis/Auralis/Aura/MainTabView.swift`

Tasks:

1. Add the missing search quick action to `GlobalChromeView`.
2. Keep context-sheet entry as the freshness access point and document that decision in the ticket notes.
3. Re-validate that account switcher, mode badge, context entry, and search entry all work from the mounted shell chrome.
4. Add a test pass or manual validation checklist for all primary surfaces using the shared chrome.

Done looks like:

- search is reachable from the actual chrome
- docs no longer claim a chrome freshness pill if the product decision is context-sheet only

### `P0-502` Receipt logging integration points

Goal for this pass:

- broaden receipt coverage from baseline slices to the important shell-wide read-only flows that already exist

Relevant docs:

- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-Remediation-Checklist.md`

Relevant code:

- `Auralis/Auralis/Aura/MainAuraView.swift`
- `Auralis/Auralis/ContextService.swift`
- `Auralis/Auralis/Accounts/AccountEventRecorder.swift`
- `Auralis/Auralis/Networking/NFTRefreshEventRecorder.swift`
- `Auralis/Auralis/Aura/Newsfeed/Components/OpenSeaLink.swift`
- `Auralis/Auralis/Aura/MainTabView.swift`
- `Auralis/Auralis/Receipts/ReceiptEventLogger.swift`
- `AuralisTests/ReceiptEventLoggerTests.swift`

Status:

- Completed for the current shell/context/action slice

Completed tasks:

1. Added an app-launch receipt from the shell startup path.
2. Added context-build receipts from `ContextService.refresh`.
3. Added receipt logging for explorer-link actions.
4. Added receipt logging for the active copy action on the newsfeed card.
5. Standardized correlation ID propagation for context refresh work.
6. Added tests for the new receipt categories.

Done looks like:

- app launch, context build, refresh, explorer open, and copy actions all leave receipts
- related steps share correlation IDs where the flow is one logical action

### `P0-302` Caching + freshness primitives

Goal for this pass:

- finish the current freshness contract without changing the UI decision about chrome

Relevant docs:

- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-Remediation-Checklist.md`

Relevant code:

- `Auralis/Auralis/Networking/NFTService.swift`
- `Auralis/Auralis/AppContext.swift`
- `Auralis/Auralis/ContextService.swift`
- `Auralis/Auralis/Aura/GlobalChromeView.swift`
- `AuralisTests/ContextSnapshotTests.swift`
- `AuralisTests/NFTServiceReceiptTests.swift`

Tasks:

1. Make the freshness ownership story explicit: `NFTService` currently owns the active refresh timestamp, `ContextService` packages it, and the inspector reads it.
2. Remove or update any docs that imply a dedicated chrome freshness pill if that is no longer the product decision.
3. Ensure the context sheet displays freshness state, last refresh time, provenance, and stale status consistently.
4. Add tests covering stale/fresh transitions at the context snapshot and inspector-data level.
5. Audit whether any additional shell surfaces need the freshness state for logic, even if not for direct display.

Done looks like:

- freshness has one clear source of truth
- the context sheet is the canonical UX for freshness detail
- docs and tests match that contract

### `P0-402` Context service + dependency boundaries

Goal for this pass:

- turn the current schema-first slice into a real shell service seam

Relevant docs:

- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-Remediation-Checklist.md`

Relevant code:

- `Auralis/Auralis/ContextService.swift`
- `Auralis/Auralis/AppContext.swift`
- `Auralis/Auralis/AppServices.swift`
- `Auralis/Auralis/Aura/MainTabView.swift`
- `Auralis/Auralis/Aura/GlobalChromeView.swift`
- `AuralisTests/ContextSnapshotTests.swift`

Tasks:

Status:

- Completed for the strengthened shell-facing context slice

Completed tasks:

1. Added `ContextBuilt` receipt emission inside `ContextService`.
2. Added payload for scope, freshness state, and provenance-safe summary data.
3. Moved the mounted chrome and context inspector onto `contextService.snapshot`.
4. Removed the redundant direct shell-state parameters from the inspector and chrome seam.
5. Expanded tests so receipt emission and snapshot-backed shell summaries are covered.

Done looks like:

- context builds are observable in receipts
- the shell relies more on one context seam and less on parallel ad hoc state reads

### `P0-303` Error handling + degraded mode

Goal for this pass:

- roll the existing degraded-mode slice through the app surfaces that already depend on the same provider state

Relevant docs:

- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-Remediation-Checklist.md`

Relevant code:

- `Auralis/Auralis/Networking/NFTService.swift`
- `Auralis/Auralis/Networking/NFTFetcher.swift`
- `Auralis/Auralis/Aura/ShellStatusView.swift`
- `Auralis/Auralis/Aura/Newsfeed/NewsFeedView.swift`
- `Auralis/Auralis/Aura/MainTabView.swift`
- `AuralisTests/NFTServiceReceiptTests.swift`

Tasks:

Status:

- Completed for the current shell-wide NFT provider-failure rollout

Completed tasks:

1. Audited the NFT-backed shell surfaces and confirmed the gap was outside the newsfeed path.
2. Reused `ShellStatusBanner` and `ShellProviderFailureStateView` in the music and NFT token roots instead of adding bespoke warnings.
3. Kept cached local content browsable on music and NFT token surfaces when refresh fails, with retry affordances matching the newsfeed behavior.
4. Kept failure copy stable by continuing to route through `NFTProviderFailurePresentation`.
5. Added coverage for blocking versus degraded presentation selection in `NFTServiceReceiptTests`.

Done looks like:

- degraded mode is not a one-screen feature
- cached local content stays visible whenever the current architecture can support it

## Recommended Order

1. `P0-101B` search action remediation
2. `P0-302` contract cleanup and validation

Why this order:

- the missing work is now mostly contractual and shell-polish cleanup
- chrome and freshness cleanup should happen against the clarified context-sheet product decision

## Explicit Non-Goals For This Pass

- do not start `P0-203`
- do not build the full dedicated `P0-403` inspector ticket
- do not reopen the product decision to add a chrome freshness pill
- do not treat shell-wide integration as "future work" if it is really completion of the current partial tickets
