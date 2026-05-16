# Auralis - Security & Architecture Audit Tickets

**Source:** Combined Security and Architecture Project-Wide Audit  
**Total tickets:** 31  
**Phases:** 1 (Security Safety) - 2 (Architecture Boundaries) - 3 (State & Concurrency) - 4 (Wallet & Agent Safety) - 5 (Testability)

---

## Phase 1 - Security Safety

### SEC-001 - Remove Provider Secrets from App Bundle

**Priority:** Critical  
**Finding:** 1  
**Files:** `Secrets.local.xcconfig`, `Auralis-Debug.xcconfig`, `Auralis-Release.xcconfig`, `Info.plist`, `ProviderKit/.../Secrets.swift`

**Problem:** Long-lived provider API key may be embedded into the app bundle via xcconfig -> Info.plist -> Bundle.infoDictionary. Even if the local file is untracked, any shipped binary can be inspected.

**Acceptance criteria:**
- Release builds do not include long-lived provider API keys in `Info.plist`, xcconfig, source, or bundle resources.
- Provider access uses a backend proxy, short-lived token broker, or explicit debug-only user-provided key.
- Archive CI step fails if `Secrets.local.xcconfig` or production-looking keys are embedded.
- `allowsLocalProviderSecrets` gate is enforced in `AppBuildEnvironment`.

---

### SEC-002 - Stop Putting Provider Keys in URL Paths

**Priority:** Critical  
**Finding:** 2  
**Files:** `ProviderKit/.../LiveProviderConfigurationResolver.swift`

**Problem:** Alchemy NFT, Data API, and RPC URLs are built with API keys interpolated directly into the path segment. Path-based keys leak through URL logging, HTTP diagnostics, proxies, caches, crash reports, screenshots, and support bundles.

**Acceptance criteria:**
- Provider keys are never placed in URL path or query segments.
- Provider endpoints are wrapped in a type that never exposes raw `absoluteString` outside the transport layer.
- All provider URL logging uses a redacted description that masks path/query.
- If a proxy/broker is not yet ready, this change lands as a prerequisite blocker.

---

### SEC-003 - Redact Wallet Addresses and Provider Material in All Logs

**Priority:** Critical  
**Finding:** 3  
**Files:** `EOAccount.swift`, `NFTFetcher.swift`, `AuraPlayLibrarySyncing.swift`, `MusicFeature/.../AuraPlayLogging.swift`

**Problem:** Full `0x...` wallet addresses appear in OSLog with `privacy: .public`. AuraPlay logging marks freeform messages public, and callers interpolate addresses into those strings. Addresses are persistent pseudonymous identifiers and must never appear in Console, crash logs, or aggregated diagnostics.

**Acceptance criteria:**
- No OSLog call logs a full wallet address with `.public` privacy.
- AuraPlay logger no longer forwards freeform sensitive interpolations as public.
- A shared `SensitiveLog` helper, or equivalent, is used for address/token/key references.
- CI scan/test catches raw `0x[a-fA-F0-9]{40}` patterns in OSLog call sites.

---

### SEC-004 - Move Shell Selection Off UserDefaults

**Priority:** Critical  
**Finding:** 4  
**Files:** `Auralis/Aura/Shell/ShellCollaborators.swift`

**Problem:** Active wallet address and chain ID are persisted to `UserDefaults`, including legacy keys. UserDefaults is unencrypted, may be included in backups, and is weak against local compromise.

**Acceptance criteria:**
- Active account/chain selection no longer writes to standard `UserDefaults`.
- Identity-adjacent selection uses Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) or protected encrypted storage.
- Legacy defaults keys are cleared during migration and privacy reset.
- `ShellSelectionSecureStoring` protocol is the dependency boundary used by `ShellCollaborators`.

---

### SEC-005 - Move ENS Resolution Cache Off Standard UserDefaults

**Priority:** High  
**Finding:** 5  
**Files:** `ENS/Sources/ENS/ENSResolutionCacheStore.swift`

**Problem:** ENS forward/reverse cache uses `UserDefaults.standard`, with reverse keys keyed by raw wallet addresses. ENS mappings reveal relationships between addresses and human-readable names.

**Acceptance criteria:**
- ENS cache no longer persists address/name mappings in standard `UserDefaults`.
- Cache uses encrypted file storage or a Keychain-backed blob with equivalent TTL behavior.
- Privacy reset clears both current and any legacy cache keys.
- TTL behavior is preserved but not relied on as a security property.

---

### SEC-006 - Replace Keychain Password Store with Production-Grade Credential Store

**Priority:** High  
**Finding:** 6  
**Files:** `Auralis/DataModels/Password.swift`

**Problem:** Current store uses `kSecAttrAccessibleAfterFirstUnlock`, makes synchronous Keychain calls, collapses load failures to `nil`, ignores delete status, and is not wired into any production flow. It is a latent footgun.

**Acceptance criteria:**
- Credential store is actor-isolated and throwing.
- Default accessibility is `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Duplicate add/update handled with add-or-update semantics.
- Delete status checked and failures surfaced.
- `SecAccessControlCreateWithFlags` path documented/stubbed for future biometric-gated secrets.
- `KeychainFailure` exposes `OSStatus` for observability.

---

### SEC-007 - Wire Credential Clearing into Privacy Reset

**Priority:** High  
**Finding:** 7  
**Files:** `Auralis/PrivacyResetService.swift`, `Auralis/DataModels/Password.swift`

**Problem:** `Password.clear()` exists but is not called during `resetLocalPrivacyData()`. A user-facing "erase my data" action must clear Keychain items.

**Acceptance criteria:**
- Credential/Keychain store is injected into `PrivacyResetService`.
- Credential clear is called during the privacy reset sequence.
- Keychain clear failures are treated as typed reset errors, not silent failures.
- Legacy `UserDefaults` keys for address/chain are also cleared in the same reset phase.

---

### SEC-008 - Add Receipt Integrity Envelope

**Priority:** High  
**Finding:** 8  
**Files:** `ReceiptsCore/.../DefaultReceiptPayloadSanitizer.swift`, `ReceiptStorage/.../SwiftDataReceiptStore.swift`, `Auralis/DataModels/StoredReceipt.swift`

**Problem:** Receipts are sanitized but mutable local records. They can be modified or deleted without detection. They are not strong audit records.

**Acceptance criteria:**
- Receipts include a per-account monotonic sequence number.
- Each receipt includes a payload hash, previous receipt hash, and chain hash.
- Latest chain head is stored in protected/Keychain storage.
- A tamper detection test fails when a stored receipt is modified or deleted outside normal flow.
- Denied and approved high-risk actions produce receipts.

---

### SEC-009 - Add NSFileProtection to SwiftData Store Files

**Priority:** Medium  
**Finding:** 19  
**Files:** SwiftData store creation sites for NFTs, receipts, accounts, identity-adjacent caches

**Problem:** No explicit file protection attributes were found for SwiftData store files.

**Acceptance criteria:**
- `NSFileProtectionCompleteUnlessOpen`, or stronger, is set on store URLs at creation.
- Threat model for jailbroken devices is documented inline or in ADR.
- Receipts and account metadata use at least `NSFileProtectionComplete`.

---

### SEC-010 - Harden External Link Policy with Path and Query Rules

**Priority:** Medium  
**Finding:** 20  
**Files:** `OperatorCore/.../ExternalLinkPolicy.swift`, `Auralis/Helpers/ExternalLinkPolicy.swift`

**Problem:** Host allowlists are strong but path-agnostic. Allowed hosts can carry malicious or privacy-leaking paths and query strings.

**Acceptance criteria:**
- External link rules include per-host allowed path prefixes.
- Query parameters are stripped or classified before display and receipt logging.
- Confirmation UI shows normalized host and route type.
- `ExternalLinkRule` is the single type governing both policy files.

---

### SEC-011 - Map Raw Provider Errors to Typed Public Errors

**Priority:** Medium  
**Finding:** 22  
**Files:** `ProviderKit/.../ProviderAbstractionError.swift`, `ProviderKit/.../AlchemyNFTService.swift`, `NFTKit/.../NFTRefreshEventRecorder.swift`

**Problem:** Raw provider errors may be converted to strings and surfaced upward. `String(describing: error)` in receipts/diagnostics can include URLs, request details, or addresses.

**Acceptance criteria:**
- Provider failures map to typed public error codes (`rateLimited`, `unauthorizedProviderConfiguration`, `providerUnavailable`, `invalidResponse`).
- Raw diagnostic strings are private and never reach user-visible surfaces or receipt payloads.
- `String(describing: error)` is not used in receipts or public-facing error paths.

---

### SEC-012 - Enforce Keychain Clear on DEBUG Fallback Exclusion from Production Archive

**Priority:** Low  
**Finding:** 30  
**Files:** `Password.swift`

**Problem:** DEBUG `UserDefaults` password fallback is correctly `#if DEBUG` guarded, but no build check confirms it is absent from production archives.

**Acceptance criteria:**
- A production build check, script phase, or test confirms debug-only credential paths are not compiled into release targets.
- Archive CI fails if any `#if DEBUG` secret/credential fallback path is reachable in release configuration.

---

## Phase 2 - Architecture Boundaries

### ARCH-001 - Declare All Direct SPM Imports in Xcode Project

**Priority:** High  
**Finding:** 11  
**Files:** `AppServices.swift`, `MainTabView.swift`, `PrivacyResetService.swift`, others importing `ENS`, `ProviderKit`, `ReceiptStorage`, `ChainProviders`

**Problem:** The app directly imports modules not declared as explicit package product dependencies in `Auralis.xcodeproj`. Build correctness depends on transitive graph stability.

**Acceptance criteria:**
- Every directly imported module in the app target has a matching explicit `packageProductDependencies` entry in the Xcode project.
- An architecture test scans app-target import statements and validates each against declared dependencies.
- CI fails on undeclared direct imports.

---

### ARCH-002 - Invert `NFTKit -> ReceiptStorage` Dependency

**Priority:** High  
**Finding:** 12  
**Files:** `NFTKit/Package.swift`

**Problem:** `NFTKit`, orchestration/domain, depends directly on `ReceiptStorage`, a SwiftData persistence adapter, violating the inward dependency rule.

**Acceptance criteria:**
- `ReceiptPersisting`, or equivalent, protocol is defined in `ReceiptsCore`.
- `ReceiptStorage` implements the protocol.
- `NFTKit` depends only on `ReceiptsCore`, not `ReceiptStorage`.
- App composition root injects the concrete `ReceiptStorage` implementation.
- Architecture test confirms `NFTKit` does not import `ReceiptStorage`.

---

### ARCH-003 - Remove `TokenStorage -> NFTKit` Dependency

**Priority:** Medium  
**Finding:** 13  
**Files:** `TokenStorage/Package.swift`, `SwiftDataTokenHoldingsStore.swift`

**Problem:** `TokenStorage` imports `NFTKit` for functionality that exists in `AuralisPrimaryModels` or should move to a smaller shared package.

**Acceptance criteria:**
- `TokenStorage` no longer imports `NFTKit`.
- Shared normalization logic lives in `AuralisPrimaryModels` or a new `EthereumAddressCore` package.
- Architecture test confirms the dependency is absent.

---

### ARCH-004 - Extract SwiftData Work Out of SwiftUI Views

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

### ARCH-005 - Slim Down `MainAuraView` and `MainTabView` Composition

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

### ARCH-006 - Centralize Ethereum Address Parsing

**Priority:** Medium  
**Finding:** 17  
**Files:** `Auralis/Helpers/String.swift`, `ProviderKit/.../String+EthereumAddress.swift`, `AccountsCore/.../AccountStore.swift`

**Problem:** Address extraction, normalization, and validation helpers are duplicated across three modules, risking drift once ENS, WalletConnect, and chain-specific formats arrive.

**Acceptance criteria:**
- A single `EthereumAddress` value type, or equivalent, is the canonical address representation.
- It lives in `AuralisPrimaryModels` or a dedicated `EthereumAddressCore` package.
- All UI, provider, account storage, and receipt modules depend on this single type.
- Duplicated helpers are removed.
- Architecture test confirms no second address-validation implementation exists.

---

### ARCH-007 - Define and Enforce Local Data Storage Classification

**Priority:** Medium  
**Finding:** 16  
**Files:** `ShellCollaborators.swift`, `HomePinnedItemsStore.swift`, `ModeState.swift`

**Problem:** Account selection, chain selection, app mode, pinned items, and UI state are mirrored across `UserDefaults`, `@AppStorage`, SwiftData, and view state with no explicit ownership rules.

**Acceptance criteria:**
- A documented `LocalDataClassification` enum, or equivalent ADR, defines `publicPreference`, `walletMetadata`, and `credential` tiers.
- Each persisted value is mapped to a storage tier and migrated accordingly: harmless UI preferences stay in `UserDefaults`, wallet identity moves to Keychain/protected storage, and credentials use Keychain.
- The mapping is documented in an ADR or inline decision comments.

---

### ARCH-008 - Complete `@Observable` Migration for `ModeState` and `AudioEngine`

**Priority:** Medium  
**Finding:** 18  
**Files:** `ModeState.swift`, `ShellStore.swift`, `AudioEngine.swift`

**Problem:** The app mixes `ObservableObject`/`@StateObject` and `@Observable`, making main-actor lifecycle and update behavior harder to reason about.

**Acceptance criteria:**
- `ModeState` is migrated to `@Observable` when next touched.
- `AudioEngine` observable UI state is migrated to `@Observable` when next touched. Worker actor stays separate per ARCH-010.
- No new `ObservableObject` types are introduced in features that also use `@Observable`.
- Migration does not regress any existing test.

---

## Phase 3 - State & Concurrency

### ARCH-009 - Move Long-Running Work Off Main Actor

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

### ARCH-010 - Centralize and Limit `Task.detached` Usage

**Priority:** Medium  
**Finding:** Phase 3 plan  
**Files:** All five `Task.detached` sites in `ShellStore` and related types

**Problem:** Five `Task.detached` sites exist. Detached tasks escape structured concurrency and make cancellation harder.

**Acceptance criteria:**
- `Task.detached` is replaced with structured alternatives (`async let`, `TaskGroup`, lifecycle-scoped tasks) at all five sites, or wrapped in cancellable service types with explicit cancel semantics.
- Any remaining `Task.detached` has a documented justification comment.
- No new `Task.detached` without review.

---

## Phase 4 - Wallet & Agent Safety

### SEC-013 - Add WalletCapabilityGate

**Priority:** High  
**Finding:** 9  
**Files:** `EOAccount.swift`, `PolicyCore/.../AppMode.swift`, `PolicyCore/.../PolicyControlledAction.swift`, `PolicyCore/.../ActionPolicyGate.swift`

**Problem:** The current gate is mode-only. Future signing, WalletConnect, plugins, and agents require a combined check over mode, account access, chain, action risk, confirmation, provenance, and receipt state.

**Acceptance criteria:**
- `WalletCapabilityGate` protocol is defined in `PolicyCore` or a new `CapabilityCore` boundary.
- Authorization requires app mode, account access type (`readonly` vs `wallet`), chain allowlist membership, action risk classification, provenance, and user confirmation state.
- Observe mode denies all signing, spending, and dApp-origin high-risk actions.
- Denials and approvals produce receipts.
- `account.access.canSign` is enforced inside `ActionPolicyGate`.
- An architecture test confirms no signing path bypasses the gate.

---

### SEC-014 - Enforce Read-Only Account Invariant and Prevent Silent `.wallet` Assignment

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

### SEC-015 - Add ENS Confirmation Gate for Future ENS Entry

**Priority:** Medium  
**Finding:** 23  
**Files:** `AccountsCore/.../AccountStore.swift`

**Problem:** ENS names are currently rejected at entry. When ENS entry is enabled, there is no resolve -> validate -> confirm flow.

**Acceptance criteria:**
- ENS resolution results in: resolve -> validate resolved address -> show resolved `0x` address in confirmation dialog -> require explicit confirmation -> persist both label and resolved address with freshness metadata.
- Resolved address passes the same checksum/allowlist validation as a directly entered address.
- Confirmation cannot be bypassed programmatically.

---

### SEC-016 - Design dApp/WebView/WalletConnect Boundary Before Implementation

**Priority:** Medium  
**Finding:** 25  
**Files:** None yet, future-readiness

**Problem:** No WebView or WalletConnect exists today. The roadmap likely requires them. Boundaries must be designed before implementation starts.

**Acceptance criteria:**
- An ADR or design document defines: ephemeral web data policy, navigation allowlist enforcement, no-arbitrary-JavaScript-bridge rule, origin-bound confirmation prompts, normalized domain display in UI, WalletConnect request preview/simulation, receipt-backed approvals, and capability-scoped sessions.
- Document is reviewed and merged before any dApp/browser/WalletConnect feature branch opens.
- A stub `SafeNavigationDelegate` with allowlist enforcement exists as the designated extension point.

---

### ARCH-011 - Document `AgentIdentityCore` Boundaries Before Expansion

**Priority:** Low now, High before agent work  
**Finding:** 32  
**Files:** `AgentIdentityCore` package

**Problem:** `AgentIdentityCore` is a stub. Adding autonomous actions, plugins, or delegated agent capabilities without explicit trust/capability boundaries is high-risk.

**Acceptance criteria:**
- An ADR or capability design doc defines: what an agent identity is, what actions it may initiate, what capability grants are required, what revocation looks like, and how agent actions are receipted.
- Document is written and reviewed before any agent execution work begins.
- Duplicate `AgentIdentityCore` references in `project.pbxproj` are cleaned up.

---

## Phase 5 - Testability & Long-Term Maintainability

### TEST-001 - Add Package-Level Tests for Critical Modules

**Priority:** Medium  
**Finding:** 26  
**Packages missing `.testTarget`:** `NFTKit`, `PolicyCore`, `OperatorCore`, `AccountsCore`, `ReceiptsCore`, `CapabilitiesCore`, `AuralisPrimaryModels`

**Acceptance criteria:**
- `NFTKitTests`, `PolicyCoreTests`, `OperatorCoreTests`, `ReceiptsCoreTests`, and `AccountsCoreTests` test targets exist.
- Each covers: sanitization, policy authorization, address normalization, receipt integrity, provider error mapping, dependency direction, and local persistence migration as applicable.
- All new targets are green in CI.

---

### TEST-002 - Add Smoke UI Tests to `AuralisUITests`

**Priority:** Medium  
**Finding:** 27  
**Files:** `AuralisUITests` target, currently empty

**Acceptance criteria:**
- Smoke tests exist for: gateway/onboarding, account switching, external link confirmation sheet, privacy reset, receipts browser, observe-mode denial flows.
- Tests run in CI on simulator.

---

### TEST-003 - Add Architecture Tests for Import Boundaries and Dependency Direction

**Priority:** Medium  
**Finding:** 9, 11, 12, 13 recurring

**Acceptance criteria:**
- Architecture test confirms app target does not import any SPM module not explicitly declared in Xcode.
- Architecture test confirms `NFTKit` does not import `ReceiptStorage`.
- Architecture test confirms `TokenStorage` does not import `NFTKit`.
- Architecture test confirms no SwiftUI view directly imports a SwiftData adapter module.
- Tests run in CI and are updated when new modules are added.

---

## Polish / Low Priority

### POLISH-001 - Guard Preview `fatalError` with `#if DEBUG`

**Priority:** Low  
**Finding:** 28  
**Files:** `Auralis/PreviewModelContainers.swift`

Return an in-memory fallback container instead of crashing where possible.

---

### POLISH-002 - Add Static URL Validity Tests for Explorer and Wallet Probe Constants

**Priority:** Low  
**Finding:** 29  
**Files:** `ExplorerCatalog.swift`, `ExternalWalletAppProbe.swift`

Force-unwrapped static URL constants are effectively safe today. Optionally add a unit test to catch future typos at compile/test time.

---

### POLISH-003 - Add Screenshot/Blur Protection Before Sensitive Screens Ship

**Priority:** Low now, required before signing/balance screens  
**Finding:** 33

Revisit before seed phrases, private keys, signing flows, heavy balance displays, or identity-heavy views exist in the app.

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
| ARCH-002 | Invert NFTKit -> ReceiptStorage Dependency | High | 2 | 12 |
| ARCH-003 | Remove TokenStorage -> NFTKit Dependency | Medium | 2 | 13 |
| ARCH-004 | Extract SwiftData Work Out of Views | Medium | 2 | 14 |
| ARCH-005 | Slim Down MainAuraView/MainTabView Composition | Medium | 2 | 15 |
| ARCH-006 | Centralize Ethereum Address Parsing | Medium | 2 | 17 |
| ARCH-007 | Define and Enforce Local Data Storage Classification | Medium | 2 | 16 |
| ARCH-008 | Complete @Observable Migration | Medium | 2 | 18 |
| ARCH-009 | Move Long-Running Work Off Main Actor | High | 3 | 10 |
| ARCH-010 | Centralize and Limit Task.detached Usage | Medium | 3 | - |
| SEC-013 | Add WalletCapabilityGate | High | 4 | 9 |
| SEC-014 | Enforce Read-Only Account Invariant | Medium | 4 | 24 |
| SEC-015 | Add ENS Confirmation Gate | Medium | 4 | 23 |
| SEC-016 | Design dApp/WebView/WalletConnect Boundary | Medium | 4 | 25 |
| ARCH-011 | Document AgentIdentityCore Boundaries | Low now | 4 | 32 |
| TEST-001 | Add Package Tests for Critical Modules | Medium | 5 | 26 |
| TEST-002 | Add Smoke UI Tests | Medium | 5 | 27 |
| TEST-003 | Add Architecture Tests for Import/Dependency Boundaries | Medium | 5 | 9/11/12 |
| POLISH-001 | Guard Preview fatalError | Low | - | 28 |
| POLISH-002 | Static URL Validity Tests | Low | - | 29 |
| POLISH-003 | Screenshot/Blur Protection Before Sensitive Screens | Low | - | 33 |
