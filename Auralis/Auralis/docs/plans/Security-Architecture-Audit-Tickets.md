# Auralis — Security & Architecture Audit Tickets

**Source:** Combined Security and Architecture Project-Wide Audit
**Open tickets:** 23
**Phases:** 3 (State & Concurrency) · 4 (Wallet & Agent Safety) · 5 (Testability)

---------------------

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
| SEC-009 | Add NSFileProtection to SwiftData Stores | Medium | 1 | 19 |
| SEC-010 | Harden External Link Policy with Path/Query Rules | Medium | 1 | 20 |
| SEC-012 | Confirm DEBUG Credential Fallback Excluded from Archive | Low | 1 | 30 |
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
