# AuraPlay — Status

This is the single living status doc for the AuraPlay rebuild. It describes what is actually in the codebase. Anything not yet built lives in `AuraPlay-Gaps.md`.

Each new phase should fold its reality into the relevant section here.

## Shape Of The Foundation

AuraPlay is the rebuild path for the Music tab inside the **Auralis** iOS app. The module lives in the local Swift package `MusicFeature/` and is composed at the app level by `MusicAssembly`.

- App target: `Auralis` (entry point `Auralis/Auralis/AuralisApp.swift`)
- Music module: `MusicFeature` Swift package at `MusicFeature/Sources/MusicFeature/`
- Module subfolders: `App/`, `Core/`, `Domain/`, `Persistence/`, `Presentation/`, `Receipts/`, `Services/`
- Composition: `Auralis/Auralis/Assemblies/MusicAssembly.swift` wires concrete services into `AuraPlayDependencies` and hands them to `MusicFeatureRootView`

## Phase 1 — Foundation

### Project & Platform

- App target name: `Auralis`; app entry `AuralisApp.swift`
- iOS 26 deployment target confirmed in `MusicFeature/Package.swift` (`.iOS("26.0")`, `.macOS("26.0")`)
- Swift 6: `swift-tools-version: 6.0` in the MusicFeature package
- Repo layout: app target under `Auralis/`, feature lives in the `MusicFeature` local package alongside other feature packages (`AccountsFeature`, `NFTLibraryFeature`, `AuraUI`, etc.)

### Info.plist & Entitlements

`Auralis/Auralis/Info.plist` declares:

- `UIBackgroundModes` = `[audio]`
- `CFBundleURLTypes` declares both `auralis` and `auraplay` schemes under `com.auralis.app`
- `LSApplicationQueriesSchemes` = `[metamask, cbwallet, rainbow, ledgerlive]`
- `AURALIS_ALCHEMY_API_KEY` placeholder bound to the xcconfig build setting
- Privacy strings: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`

The plist is the contract `AuraPlayModuleConfiguration.live(infoDictionary:)` validates at startup.

`Auralis.entitlements` exists but is empty.

### Architecture Decision

`Auralis/Auralis/docs/decisions/ADR-001-auraplay-architecture.md` is accepted.

Locked-in choices:

- Native SwiftUI + `@Observable` presentation models
- Initializer-based DI through composition roots
- Module boundary: `App/`, `Core/`, `Domain/`, `Services/`, `Presentation/`
- State ownership stays layered: `ShellStore` / `MainAuraView` / `AppRouter` (app) → `MusicAssembly` / `AuraPlayDependencies` (composition) → `@Observable` presentation models (screen) → injected playback controller over the shared `AudioEngine` (engine)
- The Music tab swaps roots through `AuraPlayTabRootView`

Related ADRs:

- ADR-002 SwiftData architecture (drives Phase 2 — see below)
- ADR-003 local-data classification
- ADR-004 Observe / Assist / Operate capability boundaries

### Dependency Injection

Auralis uses a hand-rolled **Assembly** pattern.

App-level assemblies (`Auralis/Auralis/Assemblies/`):

- `AccountAssembly`
- `HomeAssembly`
- `MainTabAssembly`
- `MusicAssembly` — owns Music tab composition
- `PolicyAssembly`
- `PrivacyAssembly`
- `ProviderAssembly`
- `ReceiptAssembly`
- `SearchAssembly`
- `ShellAssembly`
- `TokenHoldingsAssembly`

Module-level DI in MusicFeature is the public struct `AuraPlayDependencies` (`MusicFeature/Sources/MusicFeature/App/AuraPlayDependencies.swift`), an aggregate of injected protocols and values passed to `MusicFeatureRootView`:

- `any AuraPlayLibraryRepository`
- `any AuraPlayLibrarySyncing`
- `any AuraPlayPlaybackControlling`
- `any AuraPlayQueueCoordinating`
- `any AuraPlayArtworkLoading`
- `any AuraPlayLogging`
- `AuraPlayModuleConfiguration`
- `URLResolver`

Live implementations and storage-resolution utilities live next to the protocols under `MusicFeature/Sources/MusicFeature/Services/`:

- `LiveAuraPlayLibraryRepository`
- `LiveAuraPlayLibrarySyncService`
- `AuraPlayAudioEnginePlaybackController`
- `AuraPlayAudioEngineQueueCoordinator`
- `AuraPlayTrackArtworkLoader`
- `LiveAuraPlayLogger`
- `URLResolver`
- `GatewayFallbackChain`

`MusicAssembly.makeMusicFeatureDependencies(...)` is the single live composition site that wires those concretes into `AuraPlayDependencies`; `GatewayFallbackChain` exists for downstream callers that need reachability probing, but it is not a globally injected dependency today.

### Environment Configuration

Files present:

- `Auralis/Auralis/Config/Auralis-Debug.xcconfig`
- `Auralis/Auralis/Config/Auralis-Release.xcconfig`
- `Auralis/Auralis/Config/Secrets.local.xcconfig.template`
- `Auralis/Auralis/Config/Secrets.local.xcconfig` (git-ignored)

Mechanism:

- Both Debug and Release `#include? "Secrets.local.xcconfig"` and forward `AURALIS_ALCHEMY_API_KEY` into Info.plist via `INFOPLIST_KEY_AURALIS_ALCHEMY_API_KEY = $(AURALIS_ALCHEMY_API_KEY)`
- Callers read the key from `Bundle.main.infoDictionary` directly

The only secret currently flowing through this seam is `AURALIS_ALCHEMY_API_KEY`.

### Logging

`MusicFeature/Sources/MusicFeature/Services/AuraPlayLogging.swift` ships:

- `AuraPlayLogging` protocol — `func log(_ event: AuraPlayLogEvent)`
- `AuraPlayLogEvent` value type (category, level, message)
- `AuraPlayLogCategory`: `.library`, `.playback`, `.queue`, `.artwork`, `.sync` (raw values `music.library`, `music.playback`, `music.queue`, `music.artwork`, `music.sync`)
- `AuraPlayLogLevel`: `.debug`, `.info`, `.error`
- `LiveAuraPlayLogger`: `os.Logger` wrapper, subsystem `"Auralis"`, public privacy

SwiftLint enforces `auraplay_no_print` (error severity) inside the AuraPlay tree.

### Errors

The music-domain error lives at `MusicFeature/Sources/MusicFeature/Domain/AuraPlayError.swift`:

```swift
public enum AuraPlayError: Error, Equatable, LocalizedError {
    case library(String)
    case playback(String)
    case queue(String)
    case artwork(String)
    case configuration(String)
    case mediaResolution(String)
}
```

Static convenience overloads convert any `Error` into a domain message (e.g. `AuraPlayError.library(_ error: Error)` and `AuraPlayError.mediaResolution(_ error: Error)`).

### SwiftLint

`.swiftlint.yml` at repo root.

Custom rules currently enforced:

- `auraplay_no_print` (error) — blocks `print(` inside `Auralis/MusicApp/AuraPlay`
- `auraplay_no_audioengine_shared` (error) — blocks `AudioEngine.shared` inside AuraPlay
- `auraplay_ticketed_todo` (warning) — AuraPlay TODOs must look like `TODO[P1-012]`
- `icon_only_system_image_control_requires_accessibility_label` (warning) — accessibility audit holdover

`SwiftLintPlugins` ships in the package graph; CI installs SwiftLint via Homebrew and runs `swiftlint lint --config .swiftlint.yml`.

### CI

`.github/workflows/auralis-ci.yml` runs on push to `main` and on `pull_request`.

Single job `lint-build-test` on `macos-15`:

1. `actions/checkout@v4`
2. `maxim-lobanov/setup-xcode@v1` with `xcode-version: latest-stable`
3. `xcodebuild -resolvePackageDependencies -project Auralis.xcodeproj -scheme Auralis`
4. `brew install swiftlint`
5. `swiftlint lint --config .swiftlint.yml`
6. `xcodebuild build ... -destination "generic/platform=iOS"`
7. `xcodebuild test ... -destination "platform=iOS Simulator,name=iPhone 16"`

### Privacy Manifest

`Auralis/Auralis/PrivacyInfo.xcprivacy`:

- `NSPrivacyTracking` = `false`
- `NSPrivacyCollectedDataTypes` = `[]`
- `NSPrivacyAccessedAPITypes`:
  - `NSPrivacyAccessedAPICategoryUserDefaults` → `[CA92.1]`
  - `NSPrivacyAccessedAPICategoryFileTimestamp` → `[C617.1]`

### Module Configuration Guard

`MusicFeature/Sources/MusicFeature/Core/AuraPlayModuleConfiguration.swift` is the bundle-contract snapshot. `AuraPlayModuleConfiguration.live(infoDictionary:)` materializes from `Bundle.main.infoDictionary` and exposes `missingRequirements: [String]` covering background audio, the `auralis`/`auraplay` URL schemes, and the four wallet query schemes.

## Phase 2 — Persistence

### Stack

AuraPlay persistence is SwiftData. The shape is locked by ADR-002 (`docs/decisions/ADR-002-swiftdata-architecture.md`):

- one shared `ModelContainer` injected through DI
- each non-view service owns its own private `ModelContext` via `@ModelActor`
- views may use `@Query` once surfaces are query-backed; views do not orchestrate writes
- no generic repository-protocol layer beneath the framework — the only repository seam is the product-facing `AuraPlayLibraryRepository`
- `AuraPlayMediaItem` uses capability flags (`isPlayable`, `isSearchable`, `hasAudio`, `hasArtwork`) instead of a content-type inheritance tree
- search stays three-tier and Apple-native (trie + CoreSpotlight + NaturalLanguage embeddings) and remains deferred

### Container & Store

`MusicFeature/Sources/MusicFeature/Persistence/AuraPlayModelContainer.swift` is the single container factory:

- `AuraPlayModelContainer.make(inMemory: Bool) throws -> ModelContainer`
- on-disk store URL: `<Application Support>/AuraPlay/AuraPlay.store`
- in-memory mode uses `ModelConfiguration(schema:isStoredInMemoryOnly: true)`
- `AuraPlayModelContainer.resetStoreFiles(...)` cleans `.store`, `.shm`, `.wal` for logout / reset flows
- `AuraPlayModelContainer.storeURL(baseDirectory:)` exposed for test scaffolding

`MusicAssembly.makeRuntime()` constructs the container at launch and surfaces failures through `MusicRuntime.auraPlayInitializationErrorMessage` so the UI can present a recovery affordance instead of crashing.

### Schema

`MusicFeature/Sources/MusicFeature/Persistence/AuraPlaySchema.swift`:

```swift
public enum AuraPlaySchema {
    public static var models: [any PersistentModel.Type] {
        [AuraPlayMediaItem.self]
    }
}
```

The schema is currently a flat models enumeration, not a `VersionedSchema`. Only one `@Model` is registered today: `AuraPlayMediaItem`.

### `AuraPlayMediaItem`

`MusicFeature/Sources/MusicFeature/Persistence/AuraPlayMediaItem.swift` is the central persisted entity.

Key fields:

- `@Attribute(.unique) id` — equal to `sourceNFTID`
- account scope: `accountAddressRawValue`, `chainRawValue`
- NFT origin: `contractAddressRawValue`, `tokenID`, `tokenType`
- presentation: `title`, `artistName`, `collectionName`, `artworkURLString`, `playbackURLString`, `contentType`
- normalized search keys: `normalizedTitleKey`, `normalizedArtistKey`, `normalizedCollectionKey`
- capability flags: `hasArtwork`, `hasAudio`, `isPlayable`, `isSearchable`
- bookkeeping: `sourceUpdatedAtRawValue`, `createdAt`, `updatedAt`
- computed `chain: Chain` projection over `chainRawValue`

SwiftData multi-key `#Index<AuraPlayMediaItem>` macro covers:

- `(accountAddressRawValue, chainRawValue, sourceNFTID)`
- `(accountAddressRawValue, chainRawValue, contractAddressRawValue, tokenID)`
- `(accountAddressRawValue, chainRawValue, normalizedArtistKey, normalizedTitleKey, id)`
- `(accountAddressRawValue, chainRawValue)`

### Persistence Services

`MusicFeature/Sources/MusicFeature/Persistence/Services/AuraPlayMediaItemService.swift` is the `@ModelActor` that owns mutation/query work for media items.

Additional persistence support:

- `MusicFeature/Sources/MusicFeature/Persistence/SwiftDataMusicLibraryIndexer.swift` — concrete `MusicLibraryIndexing` implementation persisting the library through the model actor
- `MusicFeature/Sources/MusicFeature/Persistence/Support/AuraPlayPersistenceDescriptors.swift` — shared `FetchDescriptor` builders for predicates and sorts used across services

### Library Scope & Repository Surface

`MusicFeature/Sources/MusicFeature/Domain/AuraPlayLibraryScope.swift` captures the wallet-and-chain scope every persisted query is constrained by. It is the small value type the indexer, the sync service, and the repository all key off of.

`AuraPlayLibraryRepository` (defined under `Services/`) remains the only product-facing repository seam. `LiveAuraPlayLibraryRepository` reads the persisted graph when a scoped wallet exists and falls back to the legacy library indexer otherwise.

### Shared Wallet / NFT Models

AuraPlay does not own a separate wallet `@Model`. Wallet/account identity comes from `EOAccount` in `AuralisPrimaryModels/Sources/AuralisPrimaryPersistence/EOAccount.swift`:

- `@Attribute(.unique) address`, with `#Index` on `address`, `normalizedName`, and `(lastSelectedAt, addedAt, address)`
- `@Relationship(deleteRule: .cascade, inverse: \NFT.account) nfts: [NFT]`
- per-chain AuraPlay sync metadata encoded into `auraPlaySyncStateRawValue`, exposed through `auraPlayLastSyncedAt(for:)`, `markAuraPlaySynced(on:at:)`, `clearAuraPlaySyncState(for:)`, and `clearAllAuraPlaySyncState()`
- preferred/current chain raw values backed by `Chain`

Sibling persisted models in `AuralisPrimaryPersistence` (`NFT`, `MusicLibraryItem`, `Playlist`, `Tag`, `SearchHistoryRecord`) are shared shell/library models — not AuraPlay-owned schema. `AuraPlayMediaItem` remains the only model AuraPlay registers in its own `AuraPlaySchema`.

### Sync Path

`LiveAuraPlayLibrarySyncService` (in `MusicFeature/Sources/MusicFeature/Services/`) mirrors wallet-scoped music NFTs from the app-level model context into the AuraPlay store before the repository reads. `AuraPlayRootModel` refreshes through this sync seam before reading the library summary.

`MusicAssembly.makeMusicFeatureDependencies(...)` is the live wiring point — it constructs the sync service with both the account-level `ModelContext` and the `AuraPlayModelContainer` so the sync flow stays scope-aware.

### Test Containers

In-memory containers via `AuraPlayModelContainer.make(inMemory: true)` are the canonical entry point for `MusicFeatureTests`. Shared test-container helpers live in `AuralisTestSupport`.

## Phase 3 — Storage Resolution

### Resolver Stack

AuraPlay now owns a package-scoped storage-resolution stack under `MusicFeature/Sources/MusicFeature/Services/StorageResolution/`.

- `AuraPlayStorageResolutionConfiguration`
  Owns the primary and fallback gateway URLs. The live default uses `https://cloudflare-ipfs.com` for IPFS and `https://arweave.net` for Arweave, with public fallback gateways behind the fallback actor.
- `URIScheme`
  Classifies raw storage strings into IPFS, Arweave, HTTP, HTTPS, `data:`, or unknown inputs before any rewriting happens.
- `URLResolver`
  Synchronously resolves supported raw URIs into local file URLs or HTTPS URLs. It has no network access and no SwiftData dependency. Its only bounded I/O exception is `data:` URI decoding, which writes deterministic temp files after a 50 MB decoded-size guard.
- `GatewayFallbackChain`
  An actor above the pure resolver that HEAD-probes a primary URL, retries ordered IPFS/Arweave fallback gateways, and keeps a short in-memory failed-gateway cache so a recently dead gateway is not hammered repeatedly.
- `AuraPlayError.mediaResolution(String)`
  Carries storage-resolution failures through the existing module-scoped error surface.

The live `URLResolver` is injected through `AuraPlayDependencies`, wired in `MusicAssembly`, passed into `AuraPlayRootModel`, and used for current-track artwork URL preparation before falling back to `AuraPlayArtworkLoading`. `GatewayFallbackChain` is implemented and tested as the network-facing wrapper, but downstream metadata/audio paths still need deliberate migration before they rely on it.

The shipping boundary is intentionally narrow: Phase 3 closed the resolver and fallback seam. It did not claim that every legacy metadata, audio-engine, or image-classifier caller has already moved off app-target URL helpers.

### Phase 3 Validation

Recorded Phase 3 validation on June 7, 2026:

- `AuralisTests/AuraPlayStorageResolutionShipTests` passed, 3/3.
- `MusicFeatureTests/StorageResolutionTests` passed, 12/12.
- Full `MusicFeatureTests` passed, 28/28.
- `AuralisTests` through the Auralis-Full plan passed.
- The full Xcode project build succeeded.

The broader local-package sweep found unrelated package test debt. That follow-up is tracked in `Phase3-Followup-Package-Test-Restoration.md` and does not reopen Phase 3 storage resolution.

### Legacy Compatibility References

The legacy Music path still contains ad-hoc helpers under `Auralis/Helpers/`. These remain compatibility references and migration fixtures while downstream callers move to the AuraPlay resolver.

- `Auralis/Auralis/Helpers/StringHelpers.swift`:
  - `URLConverter.convertToPreferredHTTPS(_ urlString: String) -> Result<String, URLConversionError>` — the entry point used today for converting raw token URIs to playable HTTPS.
  - `URIConfig.uriConfigurations` declares the supported prefix → gateway map:
    - `ar://` → Arweave content scheme
    - `https://arweave.net/` → Arweave location
    - `ipfs://` → IPFS content scheme
    - `https://ipfs.io/ipfs/` → IPFS location
    - `https://alchemy.mypinata.cloud/ipfs/` → optimized Pinata location
  - `URIFormat` ranks the gateway options so existing HTTPS URLs are upgraded to the preferred gateway when possible.
  - `NormalizedResource` is the canonical (type, identifier, path) value used for deduplication after normalisation.
- `Auralis/Auralis/Helpers/URL.swift`:
  - `URL.toPinataGatewayURL()` rewrites an `ipfs://` URL to the `gateway.pinata.cloud` HTTPS form, preserving sub-path, query, and fragment.
  - `URL.sanitizedRemoteMediaURL(from rawValue: String)` is the legacy single-call sanitiser: trims whitespace, routes through `URLConverter`, falls back to `toPinataGatewayURL()` when the result is still an `ipfs://` URL.
  - `URL.isIPFS`, `URL.isSupportedRemoteMediaURL`, `URL.isVideo`, `URL.isVideoMP4` are the supporting predicates.

### Constraints That Apply Today

- The legacy resolver still mixes scheme detection, gateway selection, and URL rewriting in one helper.
- Gateway URLs in the legacy helper remain hard-coded.
- Downstream callers have only partially migrated to `URLResolver` / `GatewayFallbackChain`; the AuraPlay root uses `URLResolver` for current-track artwork, but metadata fetch, audio engine loading, and image-classifier paths still need deliberate migration. The old helpers must coexist until those paths move.

## Object Index

Use these names. Rows marked "(not yet built)" describe a planned concept that does not exist in code today.

| Concept                         | Actual name in repo                            | Location                                                                              |
| ------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------- |
| App entry                       | `AuralisApp`                                   | `Auralis/Auralis/AuralisApp.swift`                                                    |
| Music tab repository seam       | `AuraPlayLibraryRepository`                    | `MusicFeature/.../Services/AuraPlayLibraryRepository.swift`                           |
| Playback control seam           | `AuraPlayPlaybackControlling`                  | `MusicFeature/.../Services/AuraPlayPlaybackControlling.swift`                         |
| Logging seam                    | `AuraPlayLogging`                              | `MusicFeature/.../Services/AuraPlayLogging.swift`                                     |
| Music-domain error              | `AuraPlayError`                                | `MusicFeature/.../Domain/AuraPlayError.swift`                                         |
| App-level secrets typed wrapper | (not yet built)                                | —                                                                                     |
| DI plumbing                     | `*Assembly` types + `AuraPlayDependencies`     | `Auralis/Auralis/Assemblies/`, `MusicFeature/.../App/AuraPlayDependencies.swift`      |
| Build secrets                   | `Secrets.local.xcconfig` (+ template)          | `Auralis/Auralis/Config/`                                                             |
| Persistence container factory   | `AuraPlayModelContainer`                       | `MusicFeature/.../Persistence/AuraPlayModelContainer.swift`                           |
| Versioned schema + migration plan | (not yet built)                              | —                                                                                     |
| Shared wallet/account `@Model`  | `EOAccount` (shared, not AuraPlay-owned)        | `AuralisPrimaryModels/Sources/AuralisPrimaryPersistence/EOAccount.swift`             |
| AuraPlay-owned wallet service   | (not yet built — scope held by `AuraPlayLibraryScope`) | `MusicFeature/.../Domain/AuraPlayLibraryScope.swift`                          |
| Shared NFT `@Model`             | `NFT` (shared, not AuraPlay-owned)              | `AuralisPrimaryModels/Sources/AuralisPrimaryPersistence/NFT.swift`                   |
| AuraPlay-owned NFT service      | (not yet built — origin fields inline on `AuraPlayMediaItem`) | `MusicFeature/.../Persistence/AuraPlayMediaItem.swift`             |
| Media item `@Model` + service   | `AuraPlayMediaItem` + `AuraPlayMediaItemService` | `MusicFeature/.../Persistence/AuraPlayMediaItem.swift`, `.../Services/AuraPlayMediaItemService.swift` |
| Search index + three-tier search | (not yet built)                               | —                                                                                     |
| Playlist + playlist-item models | (not yet built)                                | —                                                                                     |
| Playback-state model            | (not yet built)                                | —                                                                                     |
| Deterministic seeder            | (not yet built — shared helpers in `AuralisTestSupport`) | `AuralisTestSupport/`                                                       |
| Legacy URI resolver             | `URLConverter.convertToPreferredHTTPS` (legacy, app-target) | `Auralis/Auralis/Helpers/StringHelpers.swift`                            |
| Legacy IPFS gateway rewrite     | `URL.toPinataGatewayURL()` (legacy, app-target) | `Auralis/Auralis/Helpers/URL.swift`                                                  |
| Legacy single-call sanitiser    | `URL.sanitizedRemoteMediaURL(from:)` (legacy, app-target) | `Auralis/Auralis/Helpers/URL.swift`                                          |
| Module-owned URI classifier     | `URIScheme`                                   | `MusicFeature/Sources/MusicFeature/Services/StorageResolution/URIScheme.swift`       |
| Module-owned URL resolver       | `URLResolver`                                 | `MusicFeature/Sources/MusicFeature/Services/StorageResolution/URLResolver.swift`     |
| Gateway fallback actor          | `GatewayFallbackChain`                        | `MusicFeature/Sources/MusicFeature/Services/StorageResolution/GatewayFallbackChain.swift` |

## What This Doc Is Not

- not a backlog (see `AuraPlay-Gaps.md`)
- not a substitute for ADR-001 (architecture intent), ADR-002 (persistence intent), or `AuraPlay-LLM-Context.md` (compact mental model)
- not the next-phase plan — see `AuraPlay-Phase5-Handoff.md` and `AuraPlay-Future-Work.md`
