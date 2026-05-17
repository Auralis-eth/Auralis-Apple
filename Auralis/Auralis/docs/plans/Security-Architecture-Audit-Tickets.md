# Auralis — Security & Architecture Audit Tickets

**Source:** Combined Security and Architecture Project-Wide Audit
**Total tickets:** 31
**Phases:** 1 (Security Safety) · 2 (Architecture Boundaries) · 3 (State & Concurrency) · 4 (Wallet & Agent Safety) · 5 (Testability)

---------------------

## Phase 2 — Architecture Boundaries

**Validation pass:** 2026-05-17
**Result:** All Phase 2 tickets remain valid. ARCH-005 is partially addressed by the current `ShellBootstrapDependencies` / `ShellServiceHub` work, but the ticket is still needed because the main views continue to own bootstrap and feature orchestration. No Phase 2 ticket was found to be unneeded.

| ID | Status | Validation evidence |
|---|---|---|
| ARCH-001 | Valid | App files still directly import package products that are not explicit app target package dependencies, including `ENS`, `ProviderKit`, `ReceiptStorage`, and `ChainProviders`. |
| ARCH-002 | Valid | `NFTKit/Package.swift` still declares `ReceiptStorage`, and `NFTKit/Sources/NFTKit/Support/NFTRefreshEventRecorder.swift` imports it. |
| ARCH-003 | Valid | `TokenStorage/Package.swift` still declares `NFTKit`, and `SwiftDataTokenHoldingsStore.swift` imports `NFTKit` for `ProviderTokenHolding` / `NFT.normalizedScopeComponent`. |
| ARCH-004 | Valid | Named SwiftUI views still build `FetchDescriptor`s, observe `ModelContext.didSave`, and fetch/count SwiftData records directly. |
| ARCH-005 | Valid, partially addressed | `ShellBootstrapDependencies` and `ShellServiceHub` exist, but `MainAuraView` still bootstraps the shell, audio receipts, AuraPlay storage, and dependency sets; `MainTabView` still builds `ContextService` and owns feature orchestration. |
| ARCH-006 | Valid | Address parsing remains duplicated across app helpers, `ProviderKit`, `AccountsCore`, `AuralisPrimaryModels`, and `NFTKit` normalization helpers. |
| ARCH-007 | Valid | Shell selection and pinned items still use `UserDefaults` stores, `ModeState` still uses `@AppStorage`, and no `LocalDataClassification` ADR/type exists. |
| ARCH-008 | Valid | `ModeState` and `AudioEngine` still conform to `ObservableObject`; `MainAuraView` / previews still use `@StateObject` for `ModeState` while other shell state uses `@Observable`. |

### ARCH-001 — Declare All Direct SPM Imports in Xcode Project

**Status:** Valid.
**Validated:** 2026-05-17. Direct app-target imports include `ENS`, `ProviderKit`, `ReceiptStorage`, and `ChainProviders`, but `Auralis.xcodeproj/project.pbxproj` only declares explicit app product dependencies for products such as `AuralisPrimaryModels`, `AccountsCore`, `ReceiptsCore`, `NFTKit`, `TokenStorage`, `UserDefaultsAdapters`, `AuraUI`, `AuralisShellCore`, `NFTLibraryFeature`, `MusicFeature`, and `AccountsFeature`.

**Priority:** High
**Finding:** 11
**Files:** `AppServices.swift`, `MainTabView.swift`, `PrivacyResetService.swift`, others importing `ENS`, `ProviderKit`, `ReceiptStorage`, `ChainProviders`

**Problem:** The app directly imports modules not declared as explicit package product dependencies in `Auralis.xcodeproj`. Build correctness depends on transitive graph stability.

**Acceptance criteria:**
- Every directly imported module in the app target has a matching explicit `packageProductDependencies` entry in the Xcode project.
- An architecture test scans app-target import statements and validates each against declared dependencies.
- CI fails on undeclared direct imports.

---

### ARCH-002 — Invert `NFTKit → ReceiptStorage` Dependency

**Status:** Valid.
**Validated:** 2026-05-17. `NFTKit/Package.swift` still lists `ReceiptStorage` as a package dependency and target dependency. `NFTRefreshEventRecorder.swift` imports `ReceiptStorage` to build `ReceiptStores.live(modelContext:)` from inside `NFTKit`.

**Priority:** High
**Finding:** 12
**Files:** `NFTKit/Package.swift`

**Problem:** `NFTKit` (orchestration/domain) depends directly on `ReceiptStorage` (SwiftData persistence adapter), violating the inward dependency rule.

**Acceptance criteria:**
- `ReceiptPersisting` (or equivalent) protocol is defined in `ReceiptsCore`.
- `ReceiptStorage` implements the protocol.
- `NFTKit` depends only on `ReceiptsCore`, not `ReceiptStorage`.
- App composition root injects the concrete `ReceiptStorage` implementation.
- Architecture test confirms `NFTKit` does not import `ReceiptStorage`.

---

### ARCH-003 — Remove `TokenStorage → NFTKit` Dependency

**Status:** Valid.
**Validated:** 2026-05-17. `TokenStorage/Package.swift` still depends on `NFTKit`, and `SwiftDataTokenHoldingsStore.swift` imports `NFTKit` for provider/domain types and address normalization. This still couples the persistence adapter to NFT orchestration code.

**Priority:** Medium
**Finding:** 13
**Files:** `TokenStorage/Package.swift`, `SwiftDataTokenHoldingsStore.swift`

**Problem:** `TokenStorage` imports `NFTKit` for functionality that exists in `AuralisPrimaryModels` or should move to a smaller shared package.

**Acceptance criteria:**
- `TokenStorage` no longer imports `NFTKit`.
- Shared normalization logic lives in `AuralisPrimaryModels` or a new `EthereumAddressCore` package.
- Architecture test confirms the dependency is absent.

---

### ARCH-004 — Extract SwiftData Work Out of SwiftUI Views

**Status:** Valid.
**Validated:** 2026-05-17. `HomeTabView`, `SearchRootView`, `ProfileDetailView`, and `GlobalChromeView` still create `FetchDescriptor`s, call `modelContext.fetch` / `fetchCount`, or observe `ModelContext.didSave` directly in view code.

**Priority:** Medium
**Finding:** 14
**Files:** `HomeTabView.swift`, `SearchRootView.swift`, `ProfileDetailView.swift`, `GlobalChromeView.swift`

**Problem:** Views perform non-trivial SwiftData fetch and mutation, blocking unit testing and increasing concurrency risk.

**Acceptance criteria:**
- Home, Search, Profile, and Chrome views no longer own domain/persistence fetch or mutation logic directly.
- Each replaced concern has an injectable `@MainActor` service/use-case with unit tests.
- Suggested boundaries: `HomeScopedNFTCountService`, `SearchIndexBuilder`, `ProfileAssetSummaryService`, `ChromeContextRefreshService`.
- SwiftData `ModelContext` is only accessed through adapter/service boundaries in views.

---

### ARCH-005 — Slim Down `MainAuraView` and `MainTabView` Composition

**Status:** Valid, partially addressed.
**Validated:** 2026-05-17. The current `ShellBootstrapDependencies` and `ShellServiceHub` are useful progress toward a composition root, but `MainAuraView` still performs shell initialization, audio receipt wiring, AuraPlay container setup, and dependency handoff. `MainTabView` still owns `ContextService` construction and several feature orchestration concerns.

**Priority:** Medium
**Finding:** 15
**Files:** `Auralis/Aura/MainAuraView.swift`, `Auralis/Aura/MainTabView.swift`

**Problem:** Main views carry composition, dependency wiring, feature orchestration, and state coordination that belongs elsewhere.

**Acceptance criteria:**
- Live dependency wiring is moved to `AppEnvironment` or an equivalent app-level composition root.
- Feature orchestration is moved to feature coordinators or use-case types.
- Main views are thin: they receive dependencies and render; they do not wire them.
- `AppEnvironment` is the typed dependency graph root used across the app.

---

### ARCH-006 — Centralize Ethereum Address Parsing

**Status:** Valid.
**Validated:** 2026-05-17. Address parsing/normalization remains split across `Auralis/Helpers/String.swift`, `ProviderKit/Sources/ProviderKit/Support/String+EthereumAddress.swift`, `AccountsCore/Sources/AccountsCore/Stores/AccountStore.swift`, `AuralisPrimaryModels/Sources/AuralisPrimaryModels/StoredReceipt.swift`, `ProviderKit/Sources/ProviderKit/Alchemy/AlchemyNFTService.swift`, and `NFT.normalizedScopeComponent` call sites.

**Priority:** Medium
**Finding:** 17
**Files:** `Auralis/Helpers/String.swift`, `ProviderKit/.../String+EthereumAddress.swift`, `AccountsCore/.../AccountStore.swift`

**Problem:** Address extraction, normalization, and validation helpers are duplicated across three modules, risking drift once ENS, WalletConnect, and chain-specific formats arrive.

**Acceptance criteria:**
- A single `EthereumAddress` value type (or equivalent) is the canonical address representation.
- It lives in `AuralisPrimaryModels` or a dedicated `EthereumAddressCore` package.
- All UI, provider, account storage, and receipt modules depend on this single type.
- Duplicated helpers are removed.
- Architecture test confirms no second address-validation implementation exists.

---

### ARCH-007 — Define and Enforce Local Data Storage Classification

**Status:** Valid.
**Validated:** 2026-05-17. `UserDefaultsShellSelectionPersistence` still stores shell selection in `UserDefaults`, `HomePinnedItemsStore` stores account-scoped pinned actions in `UserDefaults`, and `ModeState` stores app mode with `@AppStorage`. No `LocalDataClassification` type or ADR exists beyond this ticket.

**Priority:** Medium
**Finding:** 16
**Files:** `ShellCollaborators.swift`, `HomePinnedItemsStore.swift`, `ModeState.swift`

**Problem:** Account selection, chain selection, app mode, pinned items, and UI state are mirrored across `UserDefaults`, `@AppStorage`, SwiftData, and view state with no explicit ownership rules.

**Acceptance criteria:**
- A documented `LocalDataClassification` enum (or equivalent ADR) defines `publicPreference`, `walletMetadata`, and `credential` tiers.
- Each persisted value is mapped to a storage tier and migrated accordingly (harmless UI preferences stay in `UserDefaults`; wallet identity moves to Keychain/protected storage; credentials use Keychain).
- The mapping is documented in an ADR or inline decision comments.

---

### ARCH-008 — Complete `@Observable` Migration for `ModeState` and `AudioEngine`

**Status:** Valid.
**Validated:** 2026-05-17. `ModeState` and `AudioEngine` still conform to `ObservableObject`, with `@Published` state in both paths and `@StateObject` usage in `MainAuraView` / `MainTabView` previews. The app also contains active `@Observable` types such as `AppRouter` and `ContextService`, so the mixed observation model remains.

**Priority:** Medium
**Finding:** 18
**Files:** `ModeState.swift`, `ShellStore.swift`, `AudioEngine.swift`

**Problem:** The app mixes `ObservableObject`/`@StateObject` and `@Observable`, making main-actor lifecycle and update behavior harder to reason about.

**Acceptance criteria:**
- `ModeState` is migrated to `@Observable` when next touched.
- `AudioEngine` observable UI state is migrated to `@Observable` when next touched (worker actor stays separate per ARCH-010).
- No new `ObservableObject` types are introduced in features that also use `@Observable`.
- Migration does not regress any existing test.

---

## Phase 3 — State & Concurrency

### ARCH-009 — Move Long-Running Work Off Main Actor

**Priority:** High  
**Finding:** 10  
**Files:** `NFTKit/.../NFTService.swift`, `NFTKit/.../NFTFetcher.swift`, `Auralis/MusicApp/AI/Audio Engine/AudioEngine.swift`, `Auralis/ContextService.swift`

**Problem:** `@MainActor` services own network calls, parsing, persistence orchestration, audio file loading, and task coordination. This serializes non-UI work onto the UI isolation domain.

**Acceptance criteria:**
- NFT fetch, NFT persist orchestration, and context refresh building run in dedicated worker actors/services.
- Audio download and file IO run off the main actor.
- Each `@MainActor` type retains only view state mutation.
- Worker actor and main-actor observable state are separate types.
- View-started tasks use structured cancellation tied to view lifecycle.

---

### ARCH-010 — Centralize and Limit `Task.detached` Usage

**Priority:** Medium  
**Finding:** (Phase 3 plan)
**Files:** All five `Task.detached` sites in `ShellStore` and related types

**Problem:** Five `Task.detached` sites exist. Detached tasks escape structured concurrency and make cancellation harder.

**Acceptance criteria:**
- `Task.detached` is replaced with structured alternatives (`async let`, `TaskGroup`, lifecycle-scoped tasks) at all five sites, or wrapped in cancellable service types with explicit cancel semantics.
- Any remaining `Task.detached` has a documented justification comment.
- No new `Task.detached` without review.

---

## Phase 4 — Wallet & Agent Safety

### SEC-013 — Add WalletCapabilityGate

**Priority:** High  
**Finding:** 9  
**Files:** `EOAccount.swift`, `PolicyCore/.../AppMode.swift`, `PolicyCore/.../PolicyControlledAction.swift`, `PolicyCore/.../ActionPolicyGate.swift`

**Problem:** The current gate is mode-only. Future signing, WalletConnect, plugins, and agents require a combined check over mode, account access, chain, action risk, confirmation, provenance, and receipt state.

**Acceptance criteria:**
- `WalletCapabilityGate` protocol is defined in `PolicyCore` or a new `CapabilityCore` seam.
- Authorization requires app mode, account access type (`readonly` vs `wallet`), chain allowlist membership, action risk classification, provenance, and user confirmation state.
- Observe mode denies all signing, spending, and dApp-origin high-risk actions.
- Denials and approvals produce receipts.
- `account.access.canSign` is enforced inside `ActionPolicyGate`.
- An architecture test confirms no signing path bypasses the gate.

---

### SEC-014 — Enforce Read-Only Account Invariant and Prevent Silent `.wallet` Assignment

**Priority:** Medium  
**Finding:** 24  
**Files:** `EOAccount.swift`, `SwiftDataAccountStore.swift`

**Problem:** `EthereumAddressAccess.wallet` exists in the model but is never assigned. Future code could silently flip this without hitting a capability gate.

**Acceptance criteria:**
- `account.access.canSign` is checked in all signing adapters, WalletConnect handlers, plugin/agent call paths, and `ActionPolicyGate`.
- A test verifies all Phase 0 persisted accounts have `access == .readonly`.
- Any assignment of `.wallet` requires an explicit capability grant that goes through `WalletCapabilityGate`.
- Architecture test fails if `.wallet` assignment occurs outside the authorized upgrade path.

---

### SEC-015 — Add ENS Confirmation Gate for Future ENS Entry

**Priority:** Medium  
**Finding:** 23  
**Files:** `AccountsCore/.../AccountStore.swift`

**Problem:** ENS names are currently rejected at entry. When ENS entry is enabled, there is no resolve → validate → confirm flow.

**Acceptance criteria:**
- ENS resolution results in: resolve → validate resolved address → show resolved `0x` address in confirmation dialog → require explicit confirmation → persist both label and resolved address with freshness metadata.
- Resolved address passes the same checksum/allowlist validation as a directly entered address.
- Confirmation cannot be bypassed programmatically.

---

### SEC-016 — Design dApp/WebView/WalletConnect Boundary Before Implementation

**Priority:** Medium  
**Finding:** 25  
**Files:** (none yet — future-readiness)

**Problem:** No WebView or WalletConnect exists today (good). The roadmap likely requires them. Boundaries must be designed before implementation starts.

**Acceptance criteria:**
- An ADR or design document defines: ephemeral web data policy, navigation allowlist enforcement, no-arbitrary-JavaScript-bridge rule, origin-bound confirmation prompts, normalized domain display in UI, WalletConnect request preview/simulation, receipt-backed approvals, and capability-scoped sessions.
- Document is reviewed and merged before any dApp/browser/WalletConnect feature branch opens.
- A stub `SafeNavigationDelegate` with allowlist enforcement exists as the designated extension point.

---

### ARCH-011 — Document `AgentIdentityCore` Boundaries Before Expansion

**Priority:** Low now, High before agent work  
**Finding:** 32  
**Files:** `AgentIdentityCore` package

**Problem:** `AgentIdentityCore` is a stub. Adding autonomous actions, plugins, or delegated agent capabilities without explicit trust/capability boundaries is high-risk.

**Acceptance criteria:**
- An ADR or capability design doc defines: what an agent identity is, what actions it may initiate, what capability grants are required, what revocation looks like, and how agent actions are receipted.
- Document is written and reviewed before any agent execution work begins.
- Duplicate `AgentIdentityCore` references in `project.pbxproj` are cleaned up.

---

## Phase 5 — Testability & Long-Term Maintainability

### TEST-001 — Add Package-Level Tests for Critical Modules

**Priority:** Medium  
**Finding:** 26  
**Packages missing `.testTarget`:** `NFTKit`, `PolicyCore`, `OperatorCore`, `AccountsCore`, `ReceiptsCore`, `CapabilitiesCore`, `AuralisPrimaryModels`

**Acceptance criteria:**
- `NFTKitTests`, `PolicyCoreTests`, `OperatorCoreTests`, `ReceiptsCoreTests`, and `AccountsCoreTests` test targets exist.
- Each covers: sanitization, policy authorization, address normalization, receipt integrity, provider error mapping, dependency direction, and local persistence migration as applicable.
- All new targets are green in CI.

---

### TEST-002 — Add Smoke UI Tests to `AuralisUITests`

**Priority:** Medium  
**Finding:** 27  
**Files:** `AuralisUITests` target (currently empty)

**Acceptance criteria:**
- Smoke tests exist for: gateway/onboarding, account switching, external link confirmation sheet, privacy reset, receipts browser, observe-mode denial flows.
- Tests run in CI on simulator.

---

### TEST-003 — Add Architecture Tests for Import Boundaries and Dependency Direction

**Priority:** Medium  
**Finding:** 9, 11, 12, 13 (recurring)

**Acceptance criteria:**
- Architecture test confirms app target does not import any SPM module not explicitly declared in Xcode.
- Architecture test confirms `NFTKit` does not import `ReceiptStorage`.
- Architecture test confirms `TokenStorage` does not import `NFTKit`.
- Architecture test confirms no SwiftUI view directly imports a SwiftData adapter module.
- Tests run in CI and are updated when new modules are added.

---

## Polish / Low Priority

### POLISH-001 — Guard Preview `fatalError` with `#if DEBUG`

**Priority:** Low  
**Finding:** 28  
**Files:** `Auralis/PreviewModelContainers.swift`

Return an in-memory fallback container instead of crashing where possible.

---

### POLISH-002 — Add Static URL Validity Tests for Explorer and Wallet Probe Constants

**Priority:** Low  
**Finding:** 29  
**Files:** `ExplorerCatalog.swift`, `ExternalWalletAppProbe.swift`

Force-unwrapped static URL constants are effectively safe today. Optionally add a unit test to catch future typos at compile/test time.

---

### POLISH-003 — Add Screenshot/Blur Protection Before Sensitive Screens Ship

**Priority:** Low now, required before signing/balance screens  
**Finding:** 33

Revisit before seed phrases, private keys, signing flows, heavy balance displays, or identity-heavy views exist in the app.

---

## Security Safety Completion Notes

### SEC-008 — Add Receipt Integrity Envelope

**Verified:** Complete

Implementation notes:
- Receipts now carry per-account sequence IDs, payload hashes, previous receipt hashes, and chain hashes.
- Receipt chain heads are stored in Keychain-backed protected storage.
- Receipt integrity is end-state only: append creates complete metadata, verification is read-only, and missing integrity metadata is treated as invalid rather than repaired.
- Intentional destructive resets clear both SwiftData receipts and protected heads; failed reset deletes restore the prior protected heads.
- Tamper coverage verifies out-of-band mutation, deletion, missing metadata, missing protected heads, and orphaned protected heads.
- Policy-controlled high-risk actions now emit both denied (`policy.denied`) and approved (`policy.approved`) receipts. In the current Observe-locked app, signing, spending, and transaction drafting produce denied receipts, while plugin execution produces the approved high-risk receipt path.

### SEC-011 — Map Raw Provider Errors to Typed Public Errors

**Verified:** Complete

Implementation notes:
- NFT/provider receipt paths use typed public error codes and provider failure kinds instead of raw error strings.
- User-facing gas provider messages no longer include provider-supplied HTTP/RPC diagnostic text.
- Focused tests cover policy approval/denial receipts and gas diagnostic redaction.

---

## Summary Table

| ID | Title | Priority | Phase | Finding |
|---|---|---|---|---|
| SEC-001 | Remove Provider Secrets from App Bundle | Critical | 1 | 1 |
| SEC-002 | Stop Putting Provider Keys in URL Paths | Critical | 1 | 2 |
| SEC-003 | Redact Wallet Addresses in All Logs | Critical | 1 | 3 |
| SEC-004 | Move Shell Selection Off UserDefaults | Critical | 1 | 4 |
| SEC-005 | Move ENS Cache Off Standard UserDefaults | High | 1 | 5 |
| SEC-006 | Replace Keychain Password Store | High | 1 | 6 |
| SEC-007 | Wire Credential Clear into Privacy Reset | High | 1 | 7 |
| SEC-008 | Add Receipt Integrity Envelope | High | 1 | 8 |
| SEC-009 | Add NSFileProtection to SwiftData Stores | Medium | 1 | 19 |
| SEC-010 | Harden External Link Policy with Path/Query Rules | Medium | 1 | 20 |
| SEC-011 | Map Raw Provider Errors to Typed Public Errors | Medium | 1 | 22 |
| SEC-012 | Confirm DEBUG Credential Fallback Excluded from Archive | Low | 1 | 30 |
| ARCH-001 | Declare All Direct SPM Imports in Xcode | High | 2 | 11 |
| ARCH-002 | Invert NFTKit → ReceiptStorage Dependency | High | 2 | 12 |
| ARCH-003 | Remove TokenStorage → NFTKit Dependency | Medium | 2 | 13 |
| ARCH-004 | Extract SwiftData Work Out of Views | Medium | 2 | 14 |
| ARCH-005 | Slim Down MainAuraView/MainTabView Composition | Medium | 2 | 15 |
| ARCH-006 | Centralize Ethereum Address Parsing | Medium | 2 | 17 |
| ARCH-007 | Define and Enforce Local Data Storage Classification | Medium | 2 | 16 |
| ARCH-008 | Complete @Observable Migration | Medium | 2 | 18 |
| ARCH-009 | Move Long-Running Work Off Main Actor | High | 3 | 10 |
| ARCH-010 | Centralize and Limit Task.detached Usage | Medium | 3 | — |
| SEC-013 | Add WalletCapabilityGate | High | 4 | 9 |
| SEC-014 | Enforce Read-Only Account Invariant | Medium | 4 | 24 |
| SEC-015 | Add ENS Confirmation Gate | Medium | 4 | 23 |
| SEC-016 | Design dApp/WebView/WalletConnect Boundary | Medium | 4 | 25 |
| ARCH-011 | Document AgentIdentityCore Boundaries | Low now | 4 | 32 |
| TEST-001 | Add Package Tests for Critical Modules | Medium | 5 | 26 |
| TEST-002 | Add Smoke UI Tests | Medium | 5 | 27 |
| TEST-003 | Add Architecture Tests for Import/Dependency Boundaries | Medium | 5 | 9/11/12 |
| POLISH-001 | Guard Preview fatalError | Low | — | 28 |
| POLISH-002 | Static URL Validity Tests | Low | — | 29 |
| POLISH-003 | Screenshot/Blur Protection Before Sensitive Screens | Low | — | 33 |
