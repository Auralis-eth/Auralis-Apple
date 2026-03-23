# P0 Remediation Checklist

This checklist replaces the optimistic "completed" shorthand with a code-verified view of the current Phase 0 state.

Build status at review time:

- `BuildProject`: success

Review rule used here:

- `Ready` means the implemented code materially satisfies the original acceptance criteria.
- `Partial` means the ticket has a real baseline, but one or more acceptance criteria are still missing or explicitly narrowed.
- `Not ready` means the ticket is still scaffolding, placeholder-backed, or missing a required user-visible seam.

## Verified Summary

| Ticket | Review status | Short read |
| --- | --- | --- |
| `P0-101A` | Partial | Root shell and receipt routing exist, but deep links do not fully satisfy the original token/NFT path contract and root freshness ownership is still indirect. |
| `P0-201` | Ready | Watch-only account persistence, activation, removal, and restore flows are implemented and tested. |
| `P0-501` | Ready | Receipt schema, append-only store, sanitization, export, and reset foundation are implemented and tested. |
| `P0-101E` | Partial | Useful primitives exist, but the exact required primitive set and cross-surface adoption are incomplete. |
| `P0-101B` | Ready | The chrome is mounted globally, search/context entry exist, the Observe badge is fixed, and the ticket contract is now aligned with freshness living in the context sheet. |
| `P0-101D` | Partial | First-run, provider failure, no-receipts, and library empty states exist, but the search no-results case is still missing. |
| `P0-202` | Partial | Validation is strong, but the implementation intentionally chose lowercase canonical storage/display instead of the original checksum-display acceptance contract. |
| `P0-601` | Ready | Observe-only mode ownership, chrome display, and denial receipts are implemented for the current Phase 0 baseline. |
| `P0-204` | Ready | Per-account chain scope persistence, selection, receipts, and active refresh hook are implemented. |
| `P0-401` | Partial | `ContextSnapshot` exists, but several required fields are still placeholders and not yet provider-backed. |
| `P0-301` | Partial | Provider seams exist, but there is no single read-only provider interface owning the required balance and metadata contract end to end. |
| `P0-701A` | Partial | Structural scaffolding exists, but boundaries are not yet consistently enforced in live feature code. |
| `P0-502` | Ready | App launch, account and chain changes, NFT refresh, context build, explorer open, and the active copy action now emit receipts on the shared foundation. |
| `P0-302` | Ready | Freshness now has one shared label contract, TTL-backed stale detection, future-time clamping, and a context-inspector UX that matches the intended Phase 0 product decision. |
| `P0-402` | Partial | `ContextService` now emits context-build receipts and powers the mounted chrome plus inspector, but wider shell rollout and stricter boundary cleanup are still incomplete. |
| `P0-303` | Partial | NFT provider failures now surface consistently across the current cached NFT shell surfaces, but the broader provider-failure contract is still narrower than the original all-provider wording. |

## Ticket-By-Ticket Remediation

### `P0-101A` Root navigation structure

Status:
- Partial

Related docs:
- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-Global-Dependency-Sequence-Report.md`

Primary code:
- `Auralis/Auralis/Aura/MainAuraView.swift`
- `Auralis/Auralis/Aura/MainTabView.swift`
- `Auralis/Auralis/Aura/AppDeepLink.swift`
- `Auralis/Auralis/Aura/MainAuraShell.swift`
- `AuralisTests/AppRouterTests.swift`
- `AuralisTests/AppDeepLinkParserTests.swift`
- `AuralisTests/MainAuraShellLogicTests.swift`

Remediation tasks:
- Align deep-link parsing with the original route contract for `auralis://token/<chain>/<contract?>` and `auralis://nft/<chain>/<contract>/<tokenId>` instead of the current mostly identifier-based fallback.
- Decide whether the root-level freshness owner is `MainAuraView`, `NFTService`, or `ContextService`, then make that ownership explicit in the root shell contract.
- Add tests for the exact accepted deep-link URL shapes from the ticket text, including invalid path handling.

### `P0-201` Account model + persistence

Status:
- Ready

Related docs:
- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-202-Strategy.md`
- `Auralis/P0-204-Strategy.md`

Primary code:
- `Auralis/Auralis/Accounts/AccountStore.swift`
- `Auralis/Auralis/DataModels/EOAccount.swift`
- `AuralisTests/AccountStoreTests.swift`
- `AuralisTests/P0201FlowValidationTests.swift`

Remediation tasks:
- No blocking remediation for this ticket.
- Keep `AccountStore` as the only account CRUD seam.

### `P0-501` Receipt schema, append-only store, sanitization, export, and reset foundation

Status:
- Ready

Related docs:
- `Auralis/P0-Implementation-Order-Plan.md`

Primary code:
- `Auralis/Auralis/Receipts/ReceiptContracts.swift`
- `Auralis/Auralis/Receipts/SwiftDataReceiptStore.swift`
- `Auralis/Auralis/Receipts/DefaultReceiptPayloadSanitizer.swift`
- `Auralis/Auralis/Receipts/ReceiptResetService.swift`
- `Auralis/Auralis/DataModels/StoredReceipt.swift`
- `AuralisTests/ReceiptContractTests.swift`
- `AuralisTests/ReceiptStoreTests.swift`
- `AuralisTests/ReceiptSanitizerTests.swift`
- `AuralisTests/ReceiptResetServiceTests.swift`

Remediation tasks:
- No blocking remediation for the foundation itself.
- Keep follow-on logging expansion in `P0-502`, not here.

### `P0-101E` Design system primitives

Status:
- Partial

Related docs:
- `Auralis/P0-101E-Strategy.md`
- `Auralis/P0-Implementation-Order-Plan.md`

Primary code:
- `Auralis/Auralis/Aura/Primitives/AuraActionButton.swift`
- `Auralis/Auralis/Aura/Primitives/AuraEmptyState.swift`
- `Auralis/Auralis/Aura/Primitives/AuraErrorBanner.swift`
- `Auralis/Auralis/Aura/Primitives/AuraPill.swift`
- `Auralis/Auralis/Aura/Primitives/AuraScenicScreen.swift`
- `Auralis/Auralis/Aura/Primitives/AuraSectionHeader.swift`
- `Auralis/Auralis/Aura/Primitives/AuraSurfaceCard.swift`

Remediation tasks:
- Decide whether `ChromeHeader`, `AccountPill` or `AccountSwitcher`, `ModeBadge`, and `FreshnessPill` are separate primitives or explicitly satisfied by current types; right now that contract is not clear.
- Replace remaining bespoke badge and status styling in shell surfaces with the primitive layer so the primitives are demonstrably the shared baseline.
- Add at least one proof-of-use migration in a shell surface plus one library/detail surface that maps cleanly to the acceptance language.

### `P0-101B` Global Chrome UI

Status:
- Ready

Related docs:
- `Auralis/P0-101B-Strategy.md`
- `Auralis/P0-101B-Dependency-Note.md`
- `Auralis/P0-101B-Dependency-Report.md`
- `Auralis/P0-Implementation-Order-Plan.md`

Primary code:
- `Auralis/Auralis/Aura/GlobalChromeView.swift`
- `Auralis/Auralis/Aura/MainTabView.swift`

Remediation tasks:
- No blocking remediation for the current Phase 0 contract.
- Keep search and context entry owned by the mounted shell chrome.
- Keep freshness detail in the context sheet unless the product decision changes later.

### `P0-101D` Global error + empty-state patterns

Status:
- Partial

Related docs:
- `Auralis/P0-101D-Strategy.md`
- `Auralis/P0-101D-Tickets.md`

Primary code:
- `Auralis/Auralis/Aura/ShellStatusView.swift`
- `Auralis/Auralis/Aura/MainTabView.swift`
- `Auralis/Auralis/Aura/Auth/AddressEntryView.swift`
- `Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift`
- `Auralis/Auralis/Aura/Newsfeed/NewsFeedView.swift`

Remediation tasks:
- Implement the `no search results` shell state or formally defer that acceptance item to the search ticket chain.
- Re-check any future non-NFT read-only provider surfaces against the same shell-status contract if more providers are added.
- Add tests or manual checklist coverage for first-run, no receipts, library empty, and provider degraded states.

### `P0-202` Address validation + normalization

Status:
- Partial

Related docs:
- `Auralis/P0-202-Strategy.md`
- `Auralis/P0-202-Tickets.md`

Primary code:
- `Auralis/Auralis/Accounts/AccountStore.swift`
- `Auralis/Auralis/Aura/Auth/AddressEntryView.swift`
- `Auralis/Auralis/Aura/Auth/AddressTextField.swift`
- `AuralisTests/AccountStoreTests.swift`

Remediation tasks:
- Either update the ticket contract to bless lowercase canonical display, or implement checksum display where the original acceptance criteria require it.
- If lowercase canonical storage remains the persistence contract, document the display-vs-storage split explicitly so `P0-203` and search do not diverge.
- Add one focused test around copy behavior once a copy action exists in the UI layer.

### `P0-601` Mode system Observe v0

Status:
- Ready

Related docs:
- `Auralis/P0-601-Strategy.md`
- `Auralis/P0-601-Tickets.md`

Primary code:
- `Auralis/Auralis/ModeState.swift`
- `Auralis/Auralis/AppServices.swift`
- `Auralis/Auralis/Aura/MainTabView.swift`

Remediation tasks:
- No blocking remediation for the current Phase 0 bar.
- Keep broader action-entry rollout in `P0-602`.

### `P0-204` Chain scope settings per account

Status:
- Ready

Related docs:
- `Auralis/P0-204-Strategy.md`
- `Auralis/P0-204-Tickets.md`

Primary code:
- `Auralis/Auralis/DataModels/EOAccount.swift`
- `Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift`
- `Auralis/Auralis/Aura/MainAuraView.swift`
- `Auralis/Auralis/Accounts/AccountEventRecorder.swift`

Remediation tasks:
- No blocking remediation for the current baseline.
- Preserve this as the single live chain-scope source until `P0-401` and `P0-402` fully absorb it.

### `P0-401` Context schema v0

Status:
- Partial

Related docs:
- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-Global-Dependency-Sequence-Report.md`

Primary code:
- `Auralis/Auralis/AppContext.swift`
- `Auralis/Auralis/ContextService.swift`
- `AuralisTests/ContextSnapshotTests.swift`

Remediation tasks:
- Replace placeholder `nil` fields in balances, library pointers, and local preferences with real data sources or explicitly shrink the schema scope.
- Decide and document which fields are allowed to remain absent in Phase 0.
- Add tests proving deterministic snapshots for identical scope plus cache state.

### `P0-301` Provider abstraction

Status:
- Partial

Related docs:
- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-Global-Dependency-Sequence-Report.md`

Primary code:
- `Auralis/Auralis/Networking/ReadOnlyProviderSupport.swift`
- `Auralis/Auralis/Networking/NFTFetcher.swift`
- `AuralisTests/ProviderAbstractionTests.swift`

Remediation tasks:
- Introduce one explicit read-only provider surface that owns native balance, token metadata, and any implemented token-balance calls behind a single contract.
- Move provider selection and endpoint ownership out of feature-specific fetchers where practical.
- Add tests for native balance success and failure mapping, not just endpoint resolution and NFT inventory injection.

### `P0-701A` Layered boundaries structural scaffolding

Status:
- Partial

Related docs:
- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-Global-Dependency-Sequence-Report.md`

Primary code:
- `Auralis/Auralis/AppServices.swift`
- `Auralis/Auralis/ContextService.swift`
- `Auralis/Auralis/Aura/MainTabView.swift`
- `Auralis/Auralis/Aura/Auth/AddressEntryView.swift`
- `Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift`

Remediation tasks:
- Reduce direct `ModelContext` and persistence mutation from views where a service seam should own the operation.
- Document the intended boundaries for shell, context, providers, receipts, and storage in one current remediation source of truth.
- Add enforcement-oriented tests or lint rules later in `P0-701B`; for now, finish the structural move first.

### `P0-502` Receipt logging integration points

Status:
- Ready

Related docs:
- `Auralis/P0-Implementation-Order-Plan.md`

Primary code:
- `Auralis/Auralis/Accounts/AccountEventRecorder.swift`
- `Auralis/Auralis/Networking/NFTRefreshEventRecorder.swift`
- `Auralis/Auralis/ModeState.swift`
- `AuralisTests/NFTServiceReceiptTests.swift`

Remediation tasks:
- Keep future receipt verification and cleanup under `P0-502B`.
- Expand copy and explorer receipt coverage only when new actions/surfaces are added, not by reopening this slice.

### `P0-302` Caching + freshness primitives

Status:
- Ready

Related docs:
- `Auralis/P0-Implementation-Order-Plan.md`

Primary code:
- `Auralis/Auralis/Networking/NFTService.swift`
- `Auralis/Auralis/AppContext.swift`
- `Auralis/Auralis/ContextService.swift`
- `AuralisTests/ContextSnapshotTests.swift`
- `AuralisTests/NFTServiceReceiptTests.swift`

Remediation tasks:
- No blocking remediation for the current Phase 0 contract.
- Keep the freshness source-of-truth chain explicit: `NFTService` timestamp -> `ContextService` snapshot -> context inspector UI.
- If later product work wants broader freshness UI, treat that as new surface work instead of reintroducing parallel freshness-label logic.

### `P0-402` Context service + dependency boundaries

Status:
- Partial

Related docs:
- `Auralis/P0-Implementation-Order-Plan.md`

Primary code:
- `Auralis/Auralis/ContextService.swift`
- `Auralis/Auralis/AppServices.swift`
- `Auralis/Auralis/Aura/MainTabView.swift`
- `AuralisTests/ContextSnapshotTests.swift`

Remediation tasks:
- Keep using `ContextService` as the shell-facing seam; do not reintroduce parallel chrome/inspector state ownership.
- Continue moving additional shell reads to the context snapshot where the current shell still mixes direct account, chain, and service reads.
- Re-check every view for direct provider or provider-adjacent data access that should flow through `ContextService`.

### `P0-303` Error handling + degraded mode

Status:
- Partial

Related docs:
- `Auralis/P0-Implementation-Order-Plan.md`

Primary code:
- `Auralis/Auralis/Networking/NFTService.swift`
- `Auralis/Auralis/Networking/NFTFetcher.swift`
- `Auralis/Auralis/Aura/ShellStatusView.swift`
- `Auralis/Auralis/Aura/Newsfeed/NewsFeedView.swift`
- `AuralisTests/NFTServiceReceiptTests.swift`

Remediation tasks:
- The current NFT-backed shell rollout is in place for newsfeed, music library, and NFT token library.
- Remaining work is mostly contractual: decide whether the ticket should stay NFT-scoped for Phase 0 or expand to every future provider-backed shell surface.
- Add higher-level validation coverage if you want proof across surfaces instead of the current presentation-contract test.

## Recommended Remediation Order

1. Close the shell truth gaps first: `P0-101B`, `P0-302`, `P0-402`.
2. Then reconcile the narrowed tickets: `P0-202`, `P0-401`, `P0-301`.
3. Then expand instrumentation and resilience: `P0-502`, `P0-303`, `P0-101D`.
4. Finish with boundary cleanup: `P0-701A`.

## Exit Criteria For This Remediation Pass

- Planning docs stop calling a ticket complete when the code still carries placeholder seams.
- Every ticket above is either genuinely `Ready` or explicitly re-labeled as a baseline slice.
- The shell chrome shows the same freshness and action story the docs claim.
- Context build and shell actions emit receipts consistently enough that Phase 0 flow auditing is believable.
