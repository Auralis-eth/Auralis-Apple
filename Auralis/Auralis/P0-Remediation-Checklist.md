# P0 Remediation Checklist

This file is the working remediation checklist for the tickets recently audited against code, build status, and the original Phase 0 acceptance criteria.

## Current Build Status

- Compilation was repaired by aligning `AppContext` with the chrome/context-inspector contract in:
  - [`Auralis/AppContext.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/AppContext.swift)
- Full project build now succeeds.

## Shared Source Of Truth

Read these first before changing ticket status again:

- [`P0-Implementation-Order-Plan.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-Implementation-Order-Plan.md)
- [`P0-Global-Dependency-Sequence-Report.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-Global-Dependency-Sequence-Report.md)

## Ticket Checklist

### `P0-101A` Root navigation structure

Status: Not complete against the original acceptance criteria.

Remediation:

- [ ] Add a real Receipts root surface to top-level navigation instead of leaving receipt access to future work.
- [ ] Replace the current safe-fail receipt deep-link path with real routing for `auralis://receipts/<id>`.
- [ ] Re-verify the declared root destinations: Home, Music Library, Token List, Receipts.
- [ ] Re-run deep-link validation for account, token, NFT, and receipt routes after the Receipts surface exists.

Primary code:

- [`Auralis/Aura/MainAuraView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraView.swift)
- [`Auralis/Aura/MainTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainTabView.swift)
- [`Auralis/Aura/AppDeepLink.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/AppDeepLink.swift)
- [`Auralis/Aura/MainAuraShell.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraShell.swift)

Required docs:

- [`P0-Implementation-Order-Plan.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-Implementation-Order-Plan.md)
- [`P0-Global-Dependency-Sequence-Report.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-Global-Dependency-Sequence-Report.md)

Note:

- There is no dedicated `P0-101A` planning doc in the repo right now. If this ticket stays active, add one before further shell changes.

### `P0-201` Account model + persistence

Status: Verified enough to treat as functionally complete for now.

Remediation:

- [ ] Keep `P0-201` status as complete unless new regressions appear while fixing dependent tickets.
- [ ] Use `AccountStore` as the only account CRUD seam during follow-up work.
- [ ] Re-run account-flow tests after any `P0-202`, `P0-204`, or receipt integration changes.

Primary code:

- [`Auralis/Accounts/AccountStore.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountStore.swift)
- [`Auralis/Accounts/AccountEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountEventRecorder.swift)
- [`Auralis/DataModels/EOAccount.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/DataModels/EOAccount.swift)

Required docs:

- [`P0-201-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-201-Strategy.md)
- [`P0-201-Dependency-Report.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-201-Dependency-Report.md)
- [`P0-Implementation-Order-Plan.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-Implementation-Order-Plan.md)

### `P0-501` Receipt schema, append-only store, sanitization, export, and reset foundation

Status: Buildable, but not complete against the original schema acceptance criteria.

Remediation:

- [ ] Decide whether the original acceptance criteria still require first-class fields for actor, mode, trigger, scope, summary, details, provenance, and success/failure.
- [ ] If yes, extend the receipt contract and persisted model instead of hiding those concerns in ad hoc payload keys.
- [ ] Resolve the Swift 6 isolation warning on `SwiftDataReceiptStore`.
- [ ] Reconcile the repo docs, which currently say this ticket is complete, with the narrower schema actually implemented.
- [ ] Keep export, reset, and sanitization tests green while expanding the schema.

Primary code:

- [`Auralis/Receipts/ReceiptContracts.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Receipts/ReceiptContracts.swift)
- [`Auralis/DataModels/StoredReceipt.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/DataModels/StoredReceipt.swift)
- [`Auralis/Receipts/SwiftDataReceiptStore.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Receipts/SwiftDataReceiptStore.swift)
- [`Auralis/Receipts/DefaultReceiptPayloadSanitizer.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Receipts/DefaultReceiptPayloadSanitizer.swift)
- [`Auralis/Receipts/ReceiptResetService.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Receipts/ReceiptResetService.swift)

Required docs:

- [`P0-501-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-501-Strategy.md)
- [`P0-501-Dependency-Report.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/P0-501-Dependency-Report.md)
- [`P0-502-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-502-Strategy.md)
- [`P0-502-Tickets.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-502-Tickets.md)
- [`P0-502B-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-502B-Strategy.md)

### `P0-101E` Design system primitives

Status: Treat as complete unless later fixes require small primitive cleanup.

Remediation:

- [ ] Keep primitive work scoped to regressions or adoption gaps discovered during shell follow-up.
- [ ] Do not reopen the primitive set just because later tickets want additional product-specific views.

Primary code:

- [`Auralis/Aura/Primitives/AuraActionButton.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraActionButton.swift)
- [`Auralis/Aura/Primitives/AuraPill.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraPill.swift)
- [`Auralis/Aura/Primitives/AuraScenicScreen.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraScenicScreen.swift)
- [`Auralis/Aura/Primitives/AuraSectionHeader.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraSectionHeader.swift)
- [`Auralis/Aura/Primitives/AuraSurfaceCard.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Primitives/AuraSurfaceCard.swift)

Required docs:

- [`P0-101E-Dependency-Report.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-101E-Dependency-Report.md)
- [`P0-101B-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-101B-Strategy.md)
- [`P0-101D-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-101D-Strategy.md)

### `P0-101B` Global Chrome UI with fixed Observe presentation

Status: Build is fixed again, but the ticket still needs acceptance-criteria re-validation after `P0-101A` and `P0-601` cleanup.

Remediation:

- [ ] Re-verify chrome visibility on all primary surfaces once the Receipts surface exists.
- [ ] Re-verify freshness behavior after `P0-101C` and `P0-302` land.
- [ ] Keep the chrome mounted once at the shell level; avoid per-screen duplication.
- [ ] Reconcile the current context-inspector placeholder against `P0-403`.

Primary code:

- [`Auralis/Aura/GlobalChromeView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/GlobalChromeView.swift)
- [`Auralis/Aura/MainTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainTabView.swift)
- [`Auralis/AppContext.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/AppContext.swift)

Required docs:

- [`P0-101B-Dependency-Note.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-101B-Dependency-Note.md)
- [`P0-101B-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-101B-Strategy.md)
- [`P0-101B-Dependency-Report.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-101B-Dependency-Report.md)
- [`P0-101C-Dependency-Note.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-101C-Dependency-Note.md)
- [`P0-403-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-403-Strategy.md)

### `P0-101D` Global error + empty-state patterns

Status: Treat as complete for the current shell-status slice.

Remediation:

- [ ] Reuse the shared shell-status components instead of inventing new one-off empty/error shells.
- [ ] Re-audit only if `P0-503`, search, or token surfaces start diverging from the shared state language.

Primary code:

- [`Auralis/Aura/ShellStatusView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/ShellStatusView.swift)

Required docs:

- [`P0-101D-Dependency-Note.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-101D-Dependency-Note.md)
- [`P0-101D-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-101D-Strategy.md)
- [`P0-101D-Tickets.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-101D-Tickets.md)

### `P0-202` Address validation + normalization

Status: Partially complete. Current implementation is strict and deterministic, but it does not satisfy the original EIP-55 checksum acceptance language.

Remediation:

- [ ] Decide whether Phase 0 really needs EIP-55 checksummed display or whether lowercase canonical storage remains the intended contract.
- [ ] If EIP-55 is required, add a display-normalization path without breaking duplicate checks and persistence lookups.
- [ ] Add or expose the “copy normalized address exactly” path if this ticket still owns it.
- [ ] Reconcile ticket docs with the code if lowercase canonical form is the accepted final decision.

Primary code:

- [`Auralis/Accounts/AccountStore.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Accounts/AccountStore.swift)
- [`Auralis/Aura/Auth/AddressEntryView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressEntryView.swift)
- [`Auralis/Aura/Auth/QRScannerView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/QRScannerView.swift)
- [`Auralis/Aura/Auth/AddressTextField.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Auth/AddressTextField.swift)

Required docs:

- [`P0-202-Dependency-Note.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-202-Dependency-Note.md)
- [`P0-202-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-202-Strategy.md)
- [`P0-202-Tickets.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-202-Tickets.md)
- [`P0-203-Dependency-Note.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-203-Dependency-Note.md)

### `P0-601` Mode system Observe v0

Status: Partially complete. Mode display exists, but the ticket is not fully locked down operationally.

Remediation:

- [ ] Make the Observe state truly read-only in Phase 0, or explicitly document why mutation remains public.
- [ ] Decide whether mode belongs in the receipt schema or only in sanitized payloads.
- [ ] Wire policy-denial behavior through the real action entry points instead of leaving `ExecutePolicyGate` unused.
- [ ] Reconcile the stale `blocked` planning docs with the actual code state.

Primary code:

- [`Auralis/ModeState.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/ModeState.swift)
- [`Auralis/Aura/MainTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainTabView.swift)
- [`Auralis/Aura/GlobalChromeView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/GlobalChromeView.swift)
- [`Auralis/Networking/NFTRefreshEventRecorder.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Networking/NFTRefreshEventRecorder.swift)

Required docs:

- [`P0-601-Dependency-Note.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-601-Dependency-Note.md)
- [`P0-601-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-601-Strategy.md)
- [`P0-601-Tickets.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-601-Tickets.md)
- [`P0-602-Dependency-Note.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-602-Dependency-Note.md)
- [`P0-602-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-602-Strategy.md)

### `P0-204` Chain scope settings per account

Status: Not complete against the original acceptance criteria.

Remediation:

- [ ] Unify shell `currentChain` state with persisted account chain-scope changes so the active scope updates immediately.
- [ ] Emit receipts when chain scope changes if `P0-204` still owns that behavior.
- [ ] Trigger the intended context rebuild seam when chain scope changes instead of only saving picker values.
- [ ] Re-validate that downstream library surfaces actually honor the selected scope after the shell state is unified.
- [ ] Reconcile the ticket docs, which still describe this as blocked, with the current partial implementation.

Primary code:

- [`Auralis/Aura/Home/AccountSwitcherSheet.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/Home/AccountSwitcherSheet.swift)
- [`Auralis/DataModels/EOAccount.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/DataModels/EOAccount.swift)
- [`Auralis/Aura/MainAuraView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainAuraView.swift)
- [`Auralis/Aura/MainTabView.swift`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/Aura/MainTabView.swift)

Required docs:

- [`P0-204-Dependency-Note.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-204-Dependency-Note.md)
- [`P0-204-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-204-Strategy.md)
- [`P0-204-Tickets.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-204-Tickets.md)
- [`P0-401-Dependency-Note.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-401-Dependency-Note.md)
- [`P0-401-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-401-Strategy.md)
- [`P0-402-Dependency-Note.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-402-Dependency-Note.md)
- [`P0-402-Strategy.md`](/Users/danielbell/Dev/Auralis-Apple/Auralis/Auralis/P0-402-Strategy.md)

## Recommended Remediation Order

1. `P0-101A`
2. `P0-501`
3. `P0-601`
4. `P0-204`
5. `P0-202`
6. Re-validate `P0-101B`
7. Leave `P0-201`, `P0-101D`, and `P0-101E` in maintenance mode unless the above work proves otherwise
