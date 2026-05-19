# Auralis — Security & Architecture Audit Tickets

**Audit date:** May 17–18, 2026
**Scope:** App target + 22 local SPM packages
**Source:** Three independent audits consolidated and deduplicated

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 5 |
| Medium | 14 |
| Low | 5 |
| **Total** | **24** |

---

## Phase 1 — Security Safety Fixes
------
---

### SEC-010 · Medium · Security
**Make external-link audit failures risk-aware**

- **File:** `OperatorCore/Sources/OperatorCore/Flows/ExternalLinkOpenFlow.swift`
- **Status:** Complete — May 19, 2026
- **Why:** The previous `catch` path called `openURL` even when receipt append failed. For Web3/phishing-sensitive destinations, a sensitive handoff could occur without a durable provenance record.
- **Fix:** `ExternalLinkOpenRequest` now carries an explicit audit requirement. `ExternalLinkOpenFlow.confirm(_:)` returns an `ExternalLinkOpenOutcome`, blocks durable-audit links when receipt logging fails, and only opens degraded best-effort links with a warning outcome. NFT marketplace and explorer links opt into durable audit.
```swift
public func confirm(_ request: ExternalLinkOpenRequest) async -> ExternalLinkOpenOutcome {
    do {
        _ = try await eventLogger.recordConfirmedOpen(request)
        openURL(request.url)
        return .opened
    } catch where request.requiresDurableAudit {
        return .blockedMissingAudit
    } catch {
        openURL(request.url)
        return .openedWithAuditWarning
    }
}
```

---

## Phase 2 — Architecture Boundaries

### ARCH-001 · High · Architecture
**Split pure domain types from SwiftData `@Model` types in `AuralisPrimaryModels`**

- **File:** `AuralisPrimaryModels/Sources/AuralisPrimaryModels/NFT.swift`, `Tag.swift`
- **Why:** `NFT.swift` imports SwiftData (`@Model`) and `Tag.swift` imports UI frameworks. The domain layer is coupled to persistence and UI, blocking clean reuse in tests, extensions, server tools, and future sync engines.
- **Fix:** Introduce pure `Sendable` value types (`NFTIdentity`, `TagValue`, etc.) in the domain package. Move `@Model` types to a dedicated persistence package. Map at adapter boundaries.
```swift
public struct NFTIdentity: Hashable, Sendable {
    public let account: EthereumAddress
    public let chain: Chain
    public let contract: EthereumAddress?
    public let tokenID: String
}
```

---

### ARCH-002 · High · Architecture
**Decompose `NFTKit` into domain, provider adapter, and presentation layers**

- **File:** `NFTKit/Package.swift`, `NFTKit/Sources/NFTKit/Support/NFTFetcher.swift`
- **Why:** `NFTKit` depends on `ProviderKit`, `ChainProviders`, `ExplorerAdapter`, `ReceiptsCore`, SwiftData, and SwiftUI. Provider access, persistence, UI-facing observable state, refresh orchestration, and receipt awareness are all in one package. `AudioEngine` also imports `NFTKit`, creating a cross-domain coupling. Weakens dependency direction and makes future sync, WalletConnect, and agent workflows harder to isolate.
- **Fix:** Create explicit layers: NFT domain/use-case protocols → provider adapters → SwiftData persistence adapters → presentation state/view models → app composition. Remove `AudioEngine` → `NFTKit` import.

---

### ARCH-003 · Medium · Architecture
**Split `AppServices` into feature-scoped assemblies**

- **File:** `Auralis/AppServices.swift` (~574 lines)
- **Why:** `AppServices` wires shell, accounts, receipts, providers, music, policy, privacy reset, search, and token holdings in a single composition root. Unrelated feature changes churn app bootstrap and the type is difficult to reason about.
- **Fix:** Extract `ShellAssembly`, `ProviderAssembly`, `ReceiptAssembly`, `MusicAssembly`, `PrivacyAssembly`. Compose in a thin `AppEnvironment` holding narrow factories per feature.
```swift
@MainActor
struct AppEnvironment {
    let shellStoreFactory: @MainActor (ModelContext) -> ShellStore
    let contextServiceFactory: @MainActor (ShellStore) -> ContextService
}
```

---

### ARCH-004 · Medium · Architecture
**Extract ERC-20 sync orchestration from SwiftUI view into a use case**

- **File:** `Auralis/Aura/MainTabERC20Views.swift`
- **Why:** `syncHoldings()` fetches provider data and writes SwiftData directly from a SwiftUI view. The view is simultaneously a use case, persistence coordinator, error mapper, and renderer. Harder to test and encourages more feature logic migrating into SwiftUI.
- **Fix:** Extract `SyncERC20HoldingsUseCase` as an actor-isolated type. Inject into the view. View calls use case and renders result state only.

---

### ARCH-005 · Medium · Architecture
**Move AuraPlay live adapters and receipt logic into `MusicFeature`**

- **File:** `Auralis/MusicApp/`, `MusicFeature/`
- **Why:** `MusicFeature` only depends on `AuraUI` + `PrimaryModels`. Live `AudioEngine` (~880 lines), AuraPlay services, and receipt logic live in the app target. This blocks clean extension and isolated testing.
- **Fix:** Move playback boundary behind `MusicFeature` protocols. `AudioEngine` should depend on `AuralisPrimaryModels.NFT` only, not `NFTKit`. Migrate receipt hooks to the feature package.

---

## Phase 3 — State & Concurrency

### CONC-001 · Medium · Architecture
**Add `@MainActor` isolation to `AppRouter`**

- **File:** `Auralis/Aura/AppRouter.swift`
- **Why:** `ShellStore`, `ContextService`, and `ModeState` are `@MainActor`. `AppRouter` mutates navigation state relying on SwiftUI convention only, creating a race risk from background callbacks.
- **Fix:** `@MainActor @Observable final class AppRouter`

---

### CONC-002 · Medium · Architecture
**Remove broad `@MainActor` from service protocols that perform non-UI work**

- **File:** `NFTKit/Sources/NFTKit/Support/NFTFetcher.swift`, `MusicFeature/Sources/MusicFeature/Services/AuraPlayLibrarySyncing.swift`
- **Why:** Several service protocols and concrete types are `@MainActor` even when they coordinate sync, mapping, fetching, and persistence. This over-serializes data work onto the UI actor and risks responsiveness issues.
- **Fix:** Keep SwiftUI state and rendering `@MainActor`. Move data work into dedicated `actor`s, `@ModelActor`s, or `Sendable` services.
```swift
actor LibraryProjectionService {
    func project(_ snapshots: [SourceNFTSnapshot]) -> [AuraPlayMediaItemUpsertRequest] {
        snapshots.sorted { $0.id < $1.id }.map(makeRequest)
    }
}
```

---

### CONC-003 · Medium · Architecture
**Replace `Task.detached` usages with actor-isolated workers**

- **Files:** `SwiftDataViewServices.swift`, `NFTImageView.swift`, `PrepareNFTMetadataUseCase.swift`, `AuraPlayLibrarySyncing.swift`
- **Why:** Detached tasks escape the actor hierarchy, making cancellation and `@MainActor` updates harder to reason about and test.
- **Fix:** Prefer `Task(priority:)` from a known isolation context, or a dedicated `actor` service. Audit all four sites.

---

### CONC-004 · Medium · Architecture
**Audit `@Query` view mirrors vs `ShellStore` as single source of truth**

- **File:** Various views using `@Query` alongside `ShellStore`
- **Why:** `ShellStore` is designed as the shell source of truth. `@Query` mirrors in views can drift from `ShellStore` state, especially across rehydration and privacy reset flows.
- **Fix:** Ensure any view `@Query` is read-only presentation. All writes and selections must flow through `ShellStore`. Document the invariant or enforce it with an architecture test.

---

## Phase 4 — Wallet & Agent Safety

### WEB3-001 · High · Both
**Formalize Observe/Assist/Operate capability mode boundaries before any signing ships**

- **File:** `PolicyCore`, `AppMode`, `CapabilitiesCore`
- **Why:** Current Observe mode is hard-locked and safe. Before Assist or Operate modes are added, explicit capability grants, confirmation sheets, provenance checks, and durable receipt requirements must be in place for every high-risk action surface.
- **Fix:** Extend `AppMode` with `Assist`/`Operate`. Gate by `EthereumAddressAccess.canSign`. Add mandatory confirmation + receipt for `signMessage`, `approveSpending`, `draftTransaction`, `runPlugin`. Document the mode upgrade path in an ADR.

---

### WEB3-002 · Medium · Both
**Add chain allowlists and transaction preview hooks for future signing paths**

- **File:** `PolicyCore`, future signing flows
- **Why:** `Chain` enum + explorer/OpenSea builders exist but there is no global signing-chain gate. Transaction preview/simulation hooks are absent. These are required before any `draftTransaction` path is wired to a real signer.
- **Fix:** Add a chain allowlist checked at `PolicyControlledAction` execution. Add a mandatory preview/simulation step before `draftTransaction` that shows gas estimate, target chain, and contract info with explicit user confirmation.

---

## Phase 5 — Testability & Long-Term Maintainability

### TEST-001 · Medium · Architecture
**Extend architecture boundary tests to `MusicFeature` and `NFTLibraryFeature`**

- **File:** `AuralisTests/ArchitectureBoundaryTests.swift`
- **Why:** Boundary tests enforce `@Observable` (not `ObservableObject`) for the app target only. Both feature packages still use `ObservableObject` and can regress without detection.
- **Fix:** Add test cases scanning `MusicFeature` and `NFTLibraryFeature` Sources for `ObservableObject`. Add forbidden-import checks for the feature packages (SwiftData, UIKit, etc.).
```swift
@Test("feature modules do not use ObservableObject")
func featureModulesUseObservation() throws {
    // scan MusicFeature + NFTLibraryFeature Sources
    #expect(source.contains("ObservableObject") == false)
}
```

---

### TEST-002 · Medium · Security
**Register ENS cache, gas cache, receipt heads, and search history in `LocalDataStoragePolicy`**

- **File:** `LocalDataClassification.swift`
- **Why:** ADR-003 requires all persisted identifiers to be classified before new storage is added. ENS cache, receipt integrity heads, gas cache, and search history are missing from the policy table.
- **Fix:** Add each identifier with its classification tier (`publicPreference`, `walletMetadata`, or `credential`) and note which privacy reset phase clears it.

---

### TEST-004 · Medium · Security
**Redact provider error payloads and `error.localizedDescription` in OSLog**

- **Files:** `AlchemyNFTService.swift`, `NFTFetcher.swift`, `AuralisApp.swift`
- **Why:** Some paths log `parseErrorMessage(from:)` and `error.localizedDescription` with `.public` privacy. Provider error bodies can echo URLs, auth context, and backend diagnostic strings.
- **Fix:** Log status codes and error type names publicly. Mark provider error messages as `.private`. Add a receipt sanitizer fixture for provider error payloads.
```swift
logger.error(
    "Provider error status=\(status, privacy: .public) detail=\(error.localizedDescription, privacy: .private)"
)
```

---

### TEST-005 · Medium · Security
**Truncate or mask wallet addresses in chrome/context inspector UI**

- **File:** `ContextService`, chrome views, `ContextSnapshotTests.swift`
- **Why:** Receipts redact addresses to opaque tokens, but the chrome/inspector may show full `0x…` addresses. Screenshots and the app switcher expose these.
- **Fix:** Truncate in chrome to `first6…last4` format. Keep full value only where the user explicitly needs it (e.g. copy with confirmation). Add an app-switcher privacy overlay.
```swift
enum RedactedLog {
    static func address(_ value: String) -> String {
        guard value.count > 10 else { return "<redacted>" }
        return "\(value.prefix(6))…\(value.suffix(4))"
    }
}
```

---

### TEST-006 · Low · Architecture
**Replace force unwraps in `ExplorerCatalog` URL construction**

- **File:** `ExplorerAdapter/Sources/ExplorerAdapter/ExplorerCatalog.swift`
- **Why:** 26 `URL(string:)!` force unwraps on static HTTPS literals. Low runtime risk but a typo during maintenance silently crashes at load time.
- **Fix:** Add a non-optional URL construction helper that traps with a targeted message in `DEBUG`. Add a static test that validates all catalog URLs are well-formed.

---

### TEST-007 · Low · Architecture
**Replace force unwraps in receipt integrity code**

- **Files:** `Auralis/PrivacyResetService.swift`, `ReceiptStorage/Sources/ReceiptStorage/SwiftDataReceiptStore.swift`
- **Why:** `current!.accountSequenceID` in security/audit paths. Logically guarded, but production code should use explicit optional binding especially in tamper-evidence logic.
- **Fix:** Replace with `if let current { … }` binding throughout receipt and reset paths.

---

### TEST-008 · Low · Architecture
**Split oversized files by responsibility**

- **Files:** `AudioEngine.swift` (~880L), `MainTabView.swift` (~616L), `NFT.swift` (~525L), `SwiftDataReceiptStore.swift` (~497L)
- **Why:** Each file carries multiple distinct responsibilities, increasing review cost and the blast radius of subtle regressions.
- **Fix:**
  - `AudioEngine`: split playback loading, queue state, receipt recording
  - `MainTabView`: extract tab content views
  - `NFT.swift`: split domain value, `@Model`, and mapping (aligns with ARCH-001)
  - `SwiftDataReceiptStore`: split integrity, store, and mapper

---

### TEST-009 · Low · Architecture
**Migrate feature packages from `ObservableObject` to `@Observable`**

- **Files:** `MusicFeature/…/AuraPlayMiniPlayerView.swift`, `NFTLibraryFeature/…/NFTImageView.swift`
- **Why:** Feature packages still use `ObservableObject`/Combine wrappers. The app target enforces `@Observable` but packages are not yet covered, allowing dual state-model patterns to persist.
- **Fix:** Migrate `ObservableObject` types in `MusicFeature` and `NFTLibraryFeature` to `@Observable`. Enforce via boundary tests added in TEST-001.

---

### TEST-010 · Low · Security
**Tighten external-link root-path rules in `ExternalLinkPolicy`**

- **File:** `OperatorCore/Sources/OperatorCore/ExternalLinks/ExternalLinkPolicy.swift`
- **Why:** Some explorer and Arweave rules allow root-level `/` paths. As future wallet actions arrive, broad root-path rules could widen phishing surface if deep links or generated actions route to external domains too freely.
- **Fix:** Allow only specific generated explorer/token/address/tx URL patterns. Reserve root paths only for flows that genuinely need homepage links. Show verified host prominently in the confirmation sheet.

---

*24 tickets — 5 high, 14 medium, 5 low. Generated from three independent audit reports, May 2026.*
