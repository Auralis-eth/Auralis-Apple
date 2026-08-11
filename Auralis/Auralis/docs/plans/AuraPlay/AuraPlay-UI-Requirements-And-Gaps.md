# Auralis UI Requirements And Gaps

## Purpose

This document started as the UI inventory for the three AuraPlay media packages and their current app integration:

- `AuraPlayMediaCore`
- `AuraPlayAudioEngine`
- `AuraPlayVideoEngine`

It now also includes a companion whole-app UI audit for the surrounding Auralis surfaces that host or route into AuraPlay:

- Home
- Newsfeed
- Gas
- ERC-20 token views
- NFT token views
- Settings
- Search
- Shell, onboarding/account flows, and global chrome

It answers four questions:

1. What UI does the app need if it wants to honestly expose current package and app capabilities?
2. What UI already exists in Auralis, `MusicFeature`, or related feature packages?
3. What is placeholder-only or partially wired?
4. What is missing and should be added deliberately?

The short version: the app shell is broadly wired, Home/Search/Gas/token surfaces have useful product UI, audio now has backed system metadata, remote-command, and offline-cache controls, and video now loads wallet-scoped media items through a production-shaped player surface. A code-first pass shows the app video surface now composes `VideoPlaybackIntegrationCoordinator` and consumes Now Playing, remote commands, gateway fallback, and poster generation through it; progressive cache and offline downloads remain package seams the app does not yet expose. Shared MediaCore session contracts still need real host-app adapters before they should be exposed.

## Audit Coverage

This audit checked the files that matter for UI requirements and host integration, not fixture payloads or private implementation details that do not change the UI contract. It is still a static code/documentation audit, not a completed runtime QA pass.

| Area | Files Checked | Why They Matter |
|---|---|---|
| Shared media contracts | `AuraPlayMediaCore/Sources/AuraPlayMediaCore/AuraPlayableMedia.swift`, `MediaMetadata.swift`, `PlaybackTick.swift`, `MediaCacheContracts.swift`, `MediaDownloading.swift`, `MediaNetworkStatus.swift`, `MediaOfflineState.swift`, `MediaSessionContracts.swift`, `MediaURLResolving.swift`, `RemotePlaybackContracts.swift` | Defines common playback identity, metadata, ticks, cache/offline state, remote commands, Now Playing, and shared session concepts. |
| Audio engine contracts | `AuraPlayAudioEngine/Sources/AuraPlayAudioEngine/EngineContracts.swift`, `Effects.swift`, `AudioEngineController.swift`, `MediaCacheManaging.swift`, `MediaCacheManager.swift`, `AudioSessionManaging.swift`, `AudioSessionManager.swift`, `EngineRecoveryCoordinator.swift`, `SystemPlaybackPublishers.swift`, `AirPlayQueuePlayerController.swift`, `RemotePlayback.swift` | Defines transport, EQ, loudness, visualization, cache progress, recovery, audio session, AirPlay route, Spatial Audio policy, Now Playing, and remote command needs. |
| Audio docs and demo | `AuraPlayAudioEngine/README.md`, `Docs/Phase6ImplementationPlan.md`, `Examples/AuraPlayAudioEngineDemo/DemoScaffoldView.swift` | States host-app gates and shows the intended route picker and route-mode UI. |
| Audio tests | `AuraPlayAudioEngine/Tests/AuraPlayAudioEngineTests/AuraPlayAudioEngineContractTests.swift` via test-name grep | Confirms expected UI-facing behavior: cache progress, loudness, visualization, gapless/crossfade, recovery, Now Playing, remote commands, AirPlay queue, and spatial policy. |
| Video engine contracts | `AuraPlayVideoEngine/Sources/AuraPlayVideoEngine/VideoPlaybackTypes.swift`, `VideoPlayerController.swift`, `PlayerContainerView.swift`, `RoutePickerView.swift`, `PictureInPictureController.swift`, `IntegrationProtocols.swift`, `VideoPlaybackIntegrationCoordinator.swift`, `VideoAssetLoader.swift`, `VideoResourceLoaderCoordinator.swift`, `SubtitleTrackManager.swift`, `PlaybackSpeedController.swift`, `VideoMediaTrackManager.swift`, `VideoPlaybackQueueController.swift`, `VideoPositionPersistenceCoordinator.swift`, `StallFallbackCoordinator.swift`, `VideoPresentationAnalyzer.swift`, `VideoSpatialPlaybackPolicy.swift`, `VideoMultiviewCoordinator.swift`, `VideoFormatValidator.swift` | Defines the video player surface, transport, seeking, events, PiP, AirPlay, offline downloads, progressive cache, captions, audio variants, chapters, speed, resume, gateway fallback, HDR/posters, immersive policy, and multiview. |
| Video docs and demo | `AuraPlayVideoEngine/README.md`, `docs/decisions/ADR-004-video-streaming.md`, `docs/decisions/ADR-005-custom-player-surface.md`, `docs/release/Phase-7-Video-Engine-QA.md`, `Examples/AuraPlayVideoEngineDemo/DemoScaffoldView.swift` | Documents intended host responsibilities and manual QA for video routes, PiP, HDR, offline, and immersive playback. |
| Video tests | `AuraPlayVideoEngine/Tests/AuraPlayVideoEngineTests/VideoEngineCoreTests.swift` via test-name grep | Confirms expected UI-facing behavior around queue, multiview, stall fallback, speed, aspect/HDR, immersive policy, resume, subtitles, PiP, route picker, poster cache, offline cache, remote commands, and session events. |
| Current app video UI | `Auralis/Auralis/MusicApp/AuraPlay/Presentation/AuraPlayVideoWireframeView.swift` | Shows wallet-scoped video library entry, AVPlayer-backed playback, PiP/fullscreen/route/speed/track/chapter/resume controls, and honest unsupported states. It composes `VideoPlaybackIntegrationCoordinator` with the shared SwiftData playback-position store so Now Playing, remote commands, gateway fallback, completion reset, and resume state flow through the video engine integration path. |
| Current app audio bridge | `Auralis/Auralis/MusicApp/AuraPlay/Services/AuraPlayPlaybackRuntime.swift` | Shows which engine-backed audio controls and queue/recent surfaces are live in the app runtime. |
| Current MusicFeature UI | `MusicFeature/Sources/MusicFeature/App/MusicFeatureRootView.swift`, `Presentation/AuraPlayPlatformNavigation.swift`, `Presentation/Root/AuraPlayEntryView.swift`, `Presentation/Library/AuraPlayMusicItemDetailView.swift`, `Presentation/Library/AuraPlayMusicCollectionDetailView.swift`, `Presentation/Playback/AuraPlayMiniPlayerView.swift`, `Presentation/Playback/AuraPlayNowPlayingView.swift`, `Presentation/Playback/AuraPlayRecentlyPlayedSection.swift`, `Presentation/AuraPlayUnavailableView.swift`, `Services/AuraPlayPlaybackPresenting.swift` | Shows existing library, search/filter/sort controls, detail, mini-player, Now Playing, queue, recent, platform navigation, unavailable/retry state, system route, cache/offline controls, and visualizer placeholder UI. |
| AuraPlay app routing and composition | `Auralis/Auralis/Aura/MainAuraView.swift`, `MainTabView.swift`, `AppRouter.swift`, `Auralis/Auralis/Assemblies/MainTabAssembly.swift`, `Auralis/Auralis/Assemblies/MusicAssembly.swift` | Shows how AuraPlay is bootstrapped, how the mini-player is attached, how music/video routes are presented, and how unavailable runtime/storage states reach the UI. |
| Whole-app shell and chrome | `MainAuraView.swift`, `MainTabView.swift`, `GlobalChromeView.swift`, `ShellStatusView.swift`, `AppRouter.swift`, `MainTabSupportViews.swift`, `AuraUI/Sources/AuraUI/A11yID.swift` | Defines app launch/loading/authenticated transitions, tab routing, auxiliary surfaces, wallet/status chrome, route errors, shared status components, and accessibility identifier coverage. |
| Home and account surfaces | `HomeTabView.swift`, `HomeTabLogic.swift`, `HomeModuleCardView.swift`, `EnergyCardView.swift`, `ProfileCardView.swift`, `HomePinnedItemsStore.swift`, `HomeRecentActivityPreviewItem.swift`, `AccountSwitcherSheet.swift`, `AccountsFeature/Sources/AccountsFeature/Presentation/AddressTextField.swift`, `GuestPassCarousel.swift`, `GuestPassCard.swift` | Covers the Aura home dashboard, launcher modules, sparse/empty states, image generation entry, recent activity, account switching, onboarding address entry, ENS handling, QR/paste paths, and guest passes. |
| Newsfeed and NFT surfaces | `NewsFeedView.swift`, `NewsFeedListView.swift`, `NewsFeedListingView.swift`, `MainTabNFTViews.swift`, `NFTCollectionDetailView.swift`, plus `NFTLibraryFeature` presentation dependencies | Covers NFT browsing, refresh, detail routing, collection routing, provider failure presentation, and shared NFT detail reuse. |
| Gas and token surfaces | `Auralis/Auralis/Gas/GasFeeEstimate.swift`, `MainTabERC20Views.swift`, `ERC20HoldingRow.swift`, `ERC20HoldingsLoadingView.swift`, `ERC20HoldingsOverviewCard.swift`, `ERC20TokenDetailView.swift`, `ERC20TokenDetailPresentation.swift` | Covers gas estimates, loading/error/cached states, ERC-20 holdings sync, empty/provider/persistence failure states, and token detail routing. |
| Search, settings, and profile | `SearchRootView.swift`, `SearchLocalIndex.swift`, `SearchQueryParser.swift`, `SearchHistoryStore.swift`, `SettingsView.swift`, `ProfileDetailView.swift` | Covers global search, local result routing, search history, privacy reset, provider configuration diagnostics, profile summary, and observe-mode policy messaging. |
| Existing AuraPlay planning docs | `AuraPlay-LLM-Context.md`, `AuraPlay-Gaps.md`, `AuraPlay-Status.md`, `AuraPlay-Phase5-Handoff.md`, `AuraPlay-UI-Design-Audit-Checklist.md`, `AuraPlayMediaCore-Implementation-Plan.md` | Provides current product status, known gaps, migration guardrails, and design criteria. |

## Status Legend

| Status | Meaning |
|---|---|
| Present | User-facing UI exists and is wired to app behavior. |
| Partial | UI exists and some state is wired, but important behavior is missing or transient. |
| Placeholder | UI exists mainly as a disabled control, static preview, or status row. |
| Missing | No meaningful user-facing UI found. |
| Package Only | The package exposes the contract, but app UI/adapters do not consume it yet. |

## Whole-App UI Requirements Table

| Requirement | Source Capability | Current UI | Status | Missing Work |
|---|---|---|---|---|
| App launch and shell restore | `MainAuraView`, `ShellStore`, persisted account selection, startup deep-link replay | Bootstrap loading, authenticated tab shell, account gateway fallback, route-error sheet | Present | Runtime QA for cold-start deep links, storage-warning dismissal, account restore failure, and launch with unavailable AuraPlay storage. |
| Auth/onboarding gateway | `AccountsGatewayView`, `AddressInputView`, ENS resolver, QR scanner, paste support, guest passes | Gateway address entry, ENS/account activation, QR/paste affordances, guest pass carousel | Partial | Verify QR permission denial/retry, ENS mapping-change presentation, invalid paste feedback, Dynamic Type layout, and account activation error recovery across real devices. |
| Account switching | `AccountSwitcherHostSheet`, `AccountSwitcherSheet`, `AccountSwitching` adapters, shell account mutation | Global chrome and Home can open account switcher; chain changes and account removal route through `ShellStore` | Present | Device QA for destructive removal, chain-change failure, large saved-account lists, and route reset after account changes. |
| Global chrome | `GlobalChromeView`, `ContextService`, `ChromeContextInspectorSheet` | Current account button, mode pill, wallet status button, search button, context inspector sheet | Present | Add UI-test coverage for chrome actions; replace literal accessibility identifiers in call sites with `A11yID` constants where practical. |
| Top-level navigation | `MainTabView`, `AppRouter`, `AppTabBarVisibility`, auxiliary surfaces | Release tabs are Home, News, Gas, Music, Profile; debug/all mode can expose Receipts, Search, ERC-20, NFT Tokens as tabs; release uses auxiliary surfaces | Present | Verify auxiliary surface dismissal/back behavior and document release-vs-debug tab visibility in user-facing QA notes. |
| Route errors | `AppRouteError`, `RouteErrorScreen`, shell route-error state | Route errors surface as sheets from shell and external-link handoffs | Present | Add screenshots/QA for malformed deep links, blocked external links, and receipt-write warning paths. |
| Home dashboard | `HomeTabView`, `HomeTabLogic`, module cards, pinned actions, recent activity, account summary | Aura home shows identity, sparse state, modules, quick links, recent receipts, and creation studio | Partial | Verify Image Playground availability/failure paths, avatar/image generation cancellation, pinned action persistence, sparse-state copy, and no overlap at accessibility text sizes. |
| Home launchers | `HomeLauncherItem`, `HomeLauncherAction`, `HomeModulesPresentation`, router actions | Home routes into Search, Receipts, NFT Tokens, Music, and related app areas | Present | Confirm every launcher works in release visibility mode, especially auxiliary-only Search/NFT/ERC-20 surfaces. |
| Newsfeed | `NewsFeedView`, `NewsFeedListView`, `NewsFeedListingView`, `NFTService` refresh state | Pull-to-refresh NFT feed and shared NFT detail routing | Partial | Verify empty/loading/provider-failure states with cached and uncached content; confirm detail route reset on account/chain changes. |
| NFT token root | `NFTTokensRootView`, `NFTLibraryTokensRootView`, shared detail and collection views | NFT tokens route shows scoped NFTs, provider failures, refresh, detail, and collection navigation | Present | Add explicit QA for large collections, missing media, stale cached NFTs, and accessibility identifiers from `A11yID.NFTTokens`. |
| NFT detail and external links | `SharedNFTDetailView`, `NFTLibraryDetailView`, `ExternalLinkOpenFlow` | Shared detail is reused across News, Music, and NFT Tokens; external links require audit receipt handling | Present | Verify link confirmation, receipt-write failure, missing NFT fallback, and explorer/OpenSea routing. |
| ERC-20 holdings | `ERC20TokensRootView`, `SyncERC20HoldingsUseCase`, `TokenHolding`, context balance snapshot | Holdings root syncs token/native balances, shows loading, provider, persistence, cached-warning, empty, overview, and rows | Present | Add QA for provider warnings with cached holdings, no-token wallets, failed persistence retry, and long token names/symbols. |
| ERC-20 detail | `ERC20TokenDetailView`, `ERC20TokenDetailPresentation`, routed token route | Token detail route opens from holdings/search with account, chain, contract, and symbol context | Partial | Verify unknown metadata, unsupported chain/contract, explorer link behavior, and deep-link/search-driven detail entry. |
| Gas tracker | `GasPriceEstimateView`, `GasPriceEstimateViewModel`, `GasPricingProviding`, gas cache | Gas tab shows chain gas tracker, loading, cached/live status, pull-to-refresh, fee cards, congestion, and provider errors | Present | Add UI-test or manual checklist for offline cached estimate, provider timeout, unsupported chain, Dynamic Type, and no color-only trend indicators. |
| Search | `SearchRootView`, `SearchQueryParser`, `SearchLocalIndex`, `SearchHistoryStore`, `AppRouter` | Global search has query field, type detection, history, safety/no-results/results states, local NFT/token/profile routing, and announcements | Present | Add search indexing status/progress if index rebuilds become slow; verify history errors, dangerous/invalid input copy, and auxiliary dismissal after route selection. |
| Settings | `SettingsView`, privacy reset service, provider config diagnostics | Settings shows environment, debug provider config, local privacy reset confirmation, success/error messages, and accessibility announcements | Partial | Add explicit settings accessibility identifiers; verify privacy reset wipes every promised store, handles AuraPlay container absence, and returns shell to gateway cleanly. |
| Profile and observe mode | `ProfileDetailView`, `PolicyCore`, profile summary service | Profile summary, settings button, observe-mode locked-action cards, policy denial alerts | Partial | Add account edit/rename affordance if product wants profile management; verify policy denial copy and asset-count refresh after background updates. |
| Receipts | `ReceiptsRootView`, `ReceiptDetailView`, receipt timeline routes | Receipts are available as debug/all tab or auxiliary route and appear in context/home activity | Partial | Report currently covers receipts only as supporting UI; a dedicated receipt UI audit should verify timeline filters, integrity warnings, missing detail, and destructive reset states. |
| Accessibility coverage | `AuraUI/A11yID.swift`, shared AuraUI controls, accessibility announcements, previews | Registry exists for tabs, Home, Search, ERC-20, NFT, Receipts, Accounts, AuraPlay, RouteError, and ContextInspector; many views use native controls and Dynamic Type branches | Partial | Replace remaining literal identifiers with registry constants, register Settings/Profile/Gas primary controls if UI tests depend on them, and run Accessibility Inspector plus Dynamic Type/contrast/reduce-motion device checks. |
| Runtime/device QA | SwiftUI previews, refresh tasks, media/gas/network providers, device permissions | Many previews exist for large text and dark mode across tabs; runtime behavior is mostly async/provider-backed | Missing | This document does not prove runtime correctness. Run device QA for onboarding, QR camera permission, background/foreground refresh, account switching, provider failures, deep links, and every destructive confirmation. |

## AuraPlay UI Requirements Table

| Requirement | Source Capability | Current UI | Status | Missing Work |
|---|---|---|---|---|
| Music library root | `MusicFeature` persisted library and repository seams | `AuraPlayEntryView` shows summary, search, filter, sort, collections, tracks, and media integration rows | Present | Add fuller browse density and autocomplete only after a typed indexing/search service exists. |
| Music item detail | `MusicFeature` item/detail presentation | `AuraPlayMusicItemDetailView` shows artwork, title, artist, collection, status, play, add to queue, track info | Present | Add richer media state: cache/offline, playback history, format confidence, and source/provenance when needed. |
| Music collection detail | `MusicFeature` collection presentation | Collection detail exists and supports play/add actions from rows | Present | Add sort/filter and collection-level play/shuffle when product-ready. |
| Mini player | `AuraPlayPlaybackPresenting` | `AuraPlayMiniPlayerView` shows track, artwork, previous/play-next, compact seek, and buffering/offline/cache status for the active track | Present | Confirm mini-player placement does not obscure content after final library layout. |
| Full audio Now Playing | `AuraPlayPlaybackPresenting` plus runtime | `AuraPlayNowPlayingView` shows artwork, title, artist, scrubber, previous/next, 15-second skip buttons, queue, recent, route status, system integration, and cache/offline controls | Present | Device QA for Lock Screen controls, AirPlay, interruptions, and offline behavior. |
| Audio play/pause/resume | `AuraPlayPlaybackRuntime`, `AudioEngineController` | Mini player and Now Playing buttons call play/pause/resume; Now Playing error state exposes Retry | Present | Device QA playback recovery paths. |
| Audio previous/next | Runtime queue methods | Mini player and Now Playing buttons call previous/next | Present | Add durable queue model before promising long-lived queue state. |
| Audio skip backward/forward | `RemoteCommandEvent.skipBackward/skipForward`, runtime skip methods | Now Playing exposes 15-second skip controls and runtime seeks by 15 seconds | Present | Device QA Lock Screen skip intervals. |
| Audio seek | Runtime `seek(to:)` | Mini player and Now Playing sliders | Present | Add persisted resume after playback-state storage lands. |
| Audio queue sheet | Runtime queue presentation items | `AuraPlayQueueSheet` shows history/current/upcoming; remove and clear upcoming | Partial | Add reorder, play specific queue item, durable queue persistence, and clearer history/upcoming sections. |
| Recently played | Runtime recent presentation items | `AuraPlayRecentlyPlayedSection` supports replay/remove/clear | Partial | Persist playback history instead of relying on transient runtime history. |
| Audio artwork | `AuraPlayTrackArtworkLoader`, URL resolver | Library, detail, mini player, Now Playing use async artwork | Present | Ensure every migrated artwork path uses `URLResolver` rather than legacy helpers. |
| Audio AirPlay route picker | `AVRoutePickerView`, `AudioSessionManager` | Route picker appears in Now Playing integration panel | Present | Device QA route behavior; add status copy for active external route if desired. |
| Audio route mode | `AuraPlaybackRouteMode`, `AirPlayQueuePlayerController` | Now Playing reports the active custom-engine route mode without exposing a fake switch | Package Only | Wire explicit AirPlay-optimized handoff only after queue/position transfer and device QA are ready. |
| Audio Spatial Audio policy | `AuraSpatialAudioPolicy`, `AudioSessionManager.currentSpatialAudioEnabled()` | Now Playing reports system-route-only status without implying custom-engine spatial rendering | Present | Add policy selection only if product needs user-facing tuning. |
| Audio Now Playing system metadata | `NowPlayingPublisher` | `AuraPlayPlaybackRuntime` publishes active long-form audio metadata and clears it on stop/deinit | Present | Device QA for Lock Screen and Control Center metadata. |
| Audio remote commands | `RemoteCommandPublisher`, `MediaRemoteCommandDispatcher` | `AuraPlayPlaybackRuntime` binds system play/pause/toggle/seek/skip/next/previous events to the active transport | Present | Device QA for headphones, Lock Screen, Control Center, and route changes. |
| Audio offline/cache state | `MediaCacheManager.progress`, `AuraCachedFileState`, `CacheProgress`, `pin`, `unpin` | Now Playing subscribes to cache progress and exposes save, pin, and unpin actions; mini player shows compact buffering/offline/cache status for the active track | Present | Device QA for offline launch, failed downloads, eviction, and stale source invalidation. |
| Audio progressive play-as-download | `localFileWhenPlayable` and progressive cache progress | Now Playing cache panel and mini player show playable-partial download/buffering status while the local file continues filling | Present | Device QA poor-network progressive playback and stalled gateway recovery. |
| Audio loudness measurement | `CachedLoudnessMeasurement`, `ApproximateLoudnessAnalyzer`, normalization gain | Now Playing and Settings expose the normalization toggle; Now Playing reports measured approximate loudness/gain status | Present | Device QA representative cached tracks with and without measured loudness. |
| Audio EQ presets | `EQPreset.flat`, `.bassBoost`, `.vocalClarity`, `.custom` | Now Playing and Settings expose Flat, Bass Boost, Vocal Clarity, and Custom; Custom exposes 10 band-gain sliders wired to the live engine/defaults | Present | Device QA audible EQ changes and large-text layout. |
| Audio spoken-word dynamics | `configureForContentKind(.spokenWord)` | Now Playing reports whether music dynamics are preserved or spoken-word dynamics are active | Present | Add richer content-kind classification before exposing manual spoken-word override. |
| Audio visualizer | `AudioVisualizationPublishing`, `AudioVisualizationFrame` | Now Playing subscribes to low-frequency engine visualization frames while visible, renders live bars, pauses for Reduce Motion, and stops the tap offscreen | Present | Device QA for CPU/battery behavior during long playback. |
| Audio gapless/transition state | `GaplessScheduler`, `TransitionQuality`, recovery events | Now Playing Sound and Recovery panel reports hard-cut, gapless, brief-gap, or AutoMix transition status | Present | Device QA audible gaplessness with representative cached albums. |
| Audio crossfade/AutoMix | Test-covered AutoMix behavior | Now Playing and Settings expose a 0-8s AutoMix duration slider for upcoming prepared transitions | Present | Device QA audible transitions with cached representative media. |
| Audio session interruption/recovery | `AudioSessionEvent`, `EngineRecoveryEvent` | Runtime subscribes to recovery events and Now Playing reports ready, buffering, recovered, route recovered, interruption, or failure states | Present | Device QA AirPods connect/disconnect, calls, Siri, and background recovery. |
| Audio offline error | `AuraPlayError.mediaUnavailableOffline` and cache validation failures | Cache panel reports offline/cache failure states; offline-unavailable and corrupted-cache failures also use the transient playback warning banner | Present | Device QA offline launch with uncached and cached tracks. |
| Video entry | `AuraPlayVideoWireframeView` | App opens a wallet-scoped video library and loads selected media items through `URLResolver` | Present | Add direct video entry from item/detail cards if product wants a shorter path. |
| Video player surface | `PlayerContainerView` | Inline player has loading, empty, buffering, ended, and error overlays plus transport controls | Present | Device QA real rendering, large-text layout, and system color/contrast variants. |
| Video load | `VideoPlayerController.load(resolvedURL:)`, `VideoPlayableMedia` | Video load is driven by wallet-scoped `MusicLibraryItem` selection through `AuraPlayableMediaItem`; raw URL entry is hidden from production users | Present | Device QA with representative NFT video URLs, unsupported formats, and failed resolver output. |
| Video play/pause | `VideoPlayerController.play/pause` | A single stateful primary play/pause/replay button is wired, and `AuraPlayVideoWireframeView` composes `VideoPlaybackIntegrationCoordinator` so session events flush position and drive pause/resume consistently | Present | Device QA session interruption (calls, Siri) and PiP background policy on real hardware. |
| Video seek/progress | `PlaybackTick`, `seek(to:kind:)` | Slider, elapsed/duration labels, 15-second skip buttons, and previous/next video controls are wired directly to `VideoPlayerController` | Present | Add buffered-progress indication and richer scrubbing feedback; device QA smooth scrubbing on unbuffered positions. |
| Video speed | `PlaybackSpeedController`, `PlaybackSpeedOption` | Production options menu exposes supported playback speeds and applies changes to the current `AVPlayer` | Present | Confirm persisted speed restoration through controller/package tests and device QA audible pitch preservation. |
| Video AirPlay | `VideoRoutePickerView`, `externalPlaybackChanged` event | Route picker exists, prioritizes video devices, and app status reflects external playback events from the controller | Present | Device QA real AirPlay route discovery/mirroring and local-control behavior. |
| Video PiP | `PictureInPictureController`, `PiPState` | PiP controller is created from the player layer; button starts/stops PiP when supported and reports unavailable state | Present | Device QA on PiP-capable hardware/simulator, background auto-start, and restore behavior. |
| Video fullscreen | Host-owned expanded presentation policy | Fullscreen cover reuses the active player and player layer for 2D playback | Present | Add AVKit/Quick Look/RealityKit immersive handoff only for supported spatial content. |
| Video offline download | `ProgressiveVideoOfflineDownloadManager`, `HLSVideoOfflineDownloadManager`, `VideoOfflineManifestStore` | Package implements offline manifest/download managers; no production app control found in `AuraPlayVideoWireframeView` | Package Only | Add start/cancel/delete controls, progress, queued/downloading/available/failed/cancelled states, local playback reuse, and storage management. |
| Video progressive cache | `ProgressiveVideoCachingPipeline`, sparse byte-range cache | Package supports progressive cache plumbing; app video UI does not expose cache status or completed-local-file reuse controls | Package Only | Compose the cache pipeline into host loading if desired, then show optional cache status and retry/cancellation states. |
| Video subtitles | `SubtitleTrackManager`, `SubtitleTrack` | Subtitle menu shows Off and available tracks for the active item | Present | Persist preference in app UI state and device QA representative caption assets. |
| Video audio descriptions | `SubtitleTrackManager.availableAudioDescriptionTracks` | Audio-description rows appear when available and otherwise expose an accessible empty state | Present | Device QA with assets that include AD tracks. |
| Video audio variants | `VideoMediaTrackManager.availableAudioTracks` | Audio track menu exposes available tracks with language/default labels | Present | Device QA with multilingual assets. |
| Video chapters | `VideoMediaTrackManager.chapters` | Chapter list appears when chapter metadata exists and seeks to selected chapter start times | Present | Add scrubber markers if product wants chapter markers on the timeline. |
| Video queue | `VideoPlaybackQueueController` | App UI supports selected item plus previous/next navigation by adjacent wallet-scoped rows; package queue controller exists separately | Partial | Wire end-of-item auto-advance to a durable queue model if product wants long-form video playlists. |
| Video resume position | `VideoPositionPersistenceCoordinator`, `VideoPlaybackStateStoring` | App video playback now composes `VideoPlaybackIntegrationCoordinator` with a SwiftData-backed `AuraPlayPlaybackPositionStateService` adapter; pause/stop/disappear flush through the coordinator and completion resets use the same shared store. | Present | Physical-device QA still needs to confirm restore prompts and completion resets with real media. |
| Video Now Playing | `VideoNowPlayingPublishing`, shared Now Playing contracts | App composes the coordinator with a `VideoNowPlayingPublisherAdapter` over the shared publisher, so active video publishes Now Playing metadata | Present | Device QA Lock Screen/Control Center metadata (media type, title, artwork/poster, elapsed/duration, rate) and arbitration with audio. |
| Video remote commands | `VideoRemoteCommandStreaming`, dispatcher | App binds system remote commands to the active video coordinator via `AuraPlayPlaybackRuntime.dispatchVideoRemoteCommand` | Present | Device QA headphone/Lock Screen/Control Center commands and audio-vs-video ownership arbitration. |
| Video buffering/waiting | `VideoPlaybackState.buffering`, `VideoWaitingReason`, stalled event | Player overlays show loading/buffering/ended/error product copy with progress where appropriate | Present | Add gateway-specific recovering/retrying copy after a host gateway resolver is composed. |
| Video gateway fallback | `StallFallbackCoordinator`, gateway resolver protocol | App composes an `AuralisVideoGatewayFallbackResolver` (`VideoGatewayResolving`) into `VideoPlaybackIntegrationCoordinator`, so a stall retries an alternate gateway | Present | Surface a subtle recovering/retrying status in the UI (fallback currently reads as buffering) and device QA real gateway failover. |
| Video error handling | `VideoPlaybackError`, failure events | Overlay/status copy covers no item, unresolved URL, load failure, unsupported PiP, and playback errors | Present | Device QA unsupported formats and provider failures. |
| Video poster fallback | `PosterFrameGenerator`, `CachedPosterFrameGenerator` | App generates posters via `CachedPosterFrameGenerator` for items lacking metadata artwork (`generateMissingPosterFrames`) and renders them in library rows | Present | Extend poster reuse to video detail and Now Playing; device QA generation cost on large libraries. |
| Video aspect/orientation | `VideoPresentationAnalyzer`, `VideoPresentationInfo` | Inline player adapts to detected landscape, portrait, or square source aspect and reports the detected shape in capabilities | Present | Device QA with representative portrait, square, and landscape NFT video URLs. |
| Video HDR badge | `HDRDetector` | Capability row appears only when HDR content is detected, with display-capability copy kept honest for target hardware verification | Present | Device QA on HDR-capable and non-HDR displays. |
| Video high-frame-rate badge | `VideoPlaybackCapabilities.isHighFrameRate` | Capability row appears only when the asset reports 48 fps or higher | Present | Device QA with representative HFR content. |
| Video immersive/spatial capability | `VideoImmersivePlaybackPolicy`, `VideoPlaybackCapabilities` | Capability row reports the detected immersive profile (e.g. Apple Immersive Video, unknown immersive) as an honest badge | Partial | Add the correct host handoff control for immersive content; the inline custom layer still does not render full immersive playback. |
| Video AVKit immersive handoff | `VideoAVKitImmersiveHandoffPresenting` | No UI | Missing | Add host-owned expanded/immersive presentation action where supported. |
| Video multiview | `VideoMultiviewCoordinator` | No UI | Missing | Add participant/player grid, sync mode, route preference, network priority, and duplicate/failed state only if multiview becomes product scope. |
| Shared session launch | `SharedMediaActivityLaunchPolicy`, activity identity | Shared session card with disabled `Start Watch Together` and `Invite` | Placeholder | Build GroupActivities/SharePlay adapter, activity metadata, launch/invite UI, and share sheet registration. |
| Shared participant presence | `MediaParticipantPresence`, presence states | No real UI | Missing | Add participant row/list, local participant marker, invited/joining/lobby/ready/active/left states. |
| Shared lobby/readiness | `SharedMediaLobbyPolicy`, late-join policy | No UI | Missing | Add lobby view, ready/start controls, minimum participant logic, late-join copy. |
| Shared control attribution | `MediaSessionChangeAttribution`, `MediaControlAction` | No UI | Missing | Show lightweight notices like who paused, skipped, sought, changed queue, or selected item. |
| Shared queue identity | `SharedMediaQueueIdentity`, session snapshot | No UI | Missing | Reconcile local queue with shared queue before exposing shared playback controls. |
| Shared attachments | `SharedMediaAttachmentManifest`, metadata, mutation, policy | No UI | Missing | Add attachment tray only for user-generated/session attachments, not primary media. Include add/remove, size/state, lifecycle text. |
| Network/offline status | `MediaNetworkStatusProviding`, `MediaOfflineState` | No cross-media UI | Missing | Add offline banner/status where media requires network and no cached asset is available. |
| Search | Existing global search; AuraPlay three-tier search is deferred | AuraPlay root has local library search over title, artist, collection, content type, and chain | Partial | Add autocomplete, cross-surface result list, and indexing status after `SearchService` exists. |
| Sort/filter | Root presentation-level controls over persisted library items | AuraPlay root has playable/audio/video/missing filters and title/artist/collection/availability sort | Present | Move to typed shared service only if multiple surfaces need the same query model. |
| Playlist UI | Playlist persistence not AuraPlay-shaped | No final playlist UI | Missing | Do not add playlist controls until ordered playlist persistence/service exists. |
| Settings/preferences | Speed/subtitle/video route choices and audio offline actions exist locally | Settings now includes AuraPlay EQ, custom EQ, normalization, and AutoMix defaults; video options and audio offline controls remain contextual | Present/partial | Add storage quota/offline library management only if product wants a global media storage surface. |
| Accessibility IDs | `A11yID.AuraPlay` registry used by several screens | Library search/filter/sort, audio settings, audio custom EQ bands, offline buttons/errors, video primary controls, queue, route, cache, visualizer, and AuraPlay rows use registered constants | Present | Run Accessibility Inspector and UI automation smoke checks. |
| Device QA hooks | App QA docs list hardware-only flows | `AuraPlay-Physical-Device-QA-Suite.md` now includes the Phase 6 audio-engine release gate for AirPods, background, Lock Screen, offline, interruption, gapless, unsupported formats, and battery | Present | Execute and sign off on physical hardware before closing the release gate. |

## Whole-App Hardening Plan

| Phase | Goal | Add |
|---|---|---|
| A | Make the report QA-ready | Document release vs debug tab visibility, identify which surfaces are tabs vs auxiliary sheets, and collect screenshots for Home, News, Gas, Music, Profile, Search, NFT Tokens, ERC-20, Settings, and onboarding. |
| B | Close app-wide accessibility gaps | Replace literal accessibility identifiers with `A11yID` constants where practical, register Settings/Profile/Gas primary controls if they enter UI tests, and run Accessibility Inspector on every common task. |
| C | Verify state transitions | Device-test cold start, account restore, first account activation, guest pass activation, account switching, chain switching, account removal, logout/privacy reset, and malformed deep links. |
| D | Verify provider and offline states | Exercise uncached provider failure, cached provider failure, retry, offline gas cache, ERC-20 provider warning, NFT provider failure, and local persistence failure paths. |
| E | Verify dense and large-data layouts | Test large NFT libraries, large token lists, long account names/addresses, long ENS names, long collection titles, and accessibility Dynamic Type sizes. |
| F | Split follow-up audits if needed | Receipts, external-link audit receipts, and policy/observe-mode flows deserve a dedicated report if they become release-critical surfaces. |

## Package Integration Summary

### AuraPlayMediaCore

`AuraPlayMediaCore` is the shared vocabulary. It does not directly require screens, but it creates UI obligations once the app adopts the contracts.

| Capability | UI Needed | Current State |
|---|---|---|
| Shared playback actions | Shared play/pause/seek/next/previous/queue action controls with attribution | Missing |
| Shared session identity | Watch/listen together launch surface with activity title/subtitle/preview | Placeholder card only |
| Participant presence | Participant list with invited/joining/lobby/ready/active/left states | Missing |
| Lobby policy | Ready/start controls and late-join explanation | Missing |
| Shared queue identity | Queue reconciliation and selected item display | Missing |
| Attachments | Attachment tray/list with add/remove and size/status | Missing |
| Offline/network state | Cross-media unavailable/offline/cached states | Audio active-track cache controls present; cross-media banner still missing |
| Now Playing/remote commands | System metadata and external command handling for active media | Audio and video both wired; needs device QA |

### AuraPlayAudioEngine

Audio is product-shaped for the current release scope because `AuraPlayPlaybackRuntime`, mini player, Now Playing, Settings audio tuning, queue, recent UI, system metadata, remote commands, typed playback errors, and active-track offline controls exist. The remaining work is hardware QA plus optional advanced engine side channels.

| Capability | UI Needed | Current State |
|---|---|---|
| Core playback | Mini player, Now Playing, queue, recent | Present/partial |
| Cache/offline | Save, pin, progress, retry, cached/pinned badges | Present for active track |
| Route mode | Custom engine vs AirPlay optimized | Custom engine status only; optimized handoff not exposed |
| System route | AirPlay route picker | Present |
| Now Playing and remote commands | Lock Screen/control center metadata and command binding | Present; needs device QA |
| Visualization | Live RMS/peak visualizer | Present in Now Playing with Reduce Motion support |
| EQ/dynamics/loudness | Settings or effects sheet | Present in Settings and Now Playing |
| Recovery/interruption | Recovering/buffering/error status | Present; needs device QA |
| Spatial policy | Availability/status/policy for system route | Present as system-route-only status |

### AuraPlayVideoEngine

Video now has a production-shaped app surface for wallet-scoped 2D playback, including composed `VideoPlaybackIntegrationCoordinator`, Now Playing, remote commands, gateway fallback, and poster generation. Offline video downloads, immersive handoff, and multiview remain package-backed or future product scope.

| Capability | UI Needed | Current State |
|---|---|---|
| Player surface | Inline player with production controls | Present |
| Library-driven load | Open/play video from media item | Present |
| PiP | PiP start/stop/state/restore | Present; needs device QA |
| Fullscreen/expanded | Host-owned fullscreen or immersive handoff | Present for 2D fullscreen cover; immersive handoff missing |
| Offline | Download/cancel/progress/local reuse | Missing |
| Subtitles/audio tracks | Menus with preferences | Present; preference persistence follow-up |
| Chapters | Chapter list/markers | Present when metadata exists |
| Queue | Video queue list and next/previous | Partial wallet-scoped list |
| Resume | Continue prompt and persisted position | Present with local store |
| Poster/HDR/aspect | Poster fallback, HDR/HFR badges, aspect-aware layout | HDR/HFR/aspect present; poster fallback present in library rows |
| Gateway fallback | Recovering state and retry path | Resolver composed; explicit recovering-status UI still missing |
| Multiview | Participant grid/sync/route priority controls | Missing |
| Immersive/spatial | Honest badges and host handoff controls | Honest badge present; host handoff control missing |

## Completed Implementation Pass

| Phase | Result |
|---|---|
| 1 | Audio UI is honest: skip controls and runtime now use 15-second intervals, dead controls were removed, and integration copy reflects backed or unavailable behavior. |
| 2 | Audio host integrations are wired for current scope: Now Playing metadata, remote commands, active-track cache progress, save offline, pin, and unpin. AirPlay-optimized queue handoff remains deliberately unexposed. |
| 3 | Video now loads wallet-scoped media items instead of raw URL input, with production state overlays, transport controls, speed options, AirPlay route picker, PiP, fullscreen, tracks, chapters, and resume position. |
| 4 | AuraPlay root discovery now has local search, media/availability filters, and sort controls over persisted wallet-scoped library items. |
| 5 | Video capability UI now uses package-backed aspect, HDR, and HFR analysis; audio errors expose a retry action; remaining AuraPlay literals now use `A11yID` constants. |
| 6 | Audio visualization is wired end-to-end: `MusicFeature` owns a package-neutral visualization presentation contract, the app runtime maps engine RMS/peak frames into live bars, Now Playing starts/stops the stream with view lifecycle, and Reduce Motion pauses animation. |
| 7 | Audio Engine v1 UI is wired across Now Playing, mini player, and Settings: buffering/download progress, EQ/custom EQ, normalization, AutoMix, offline save/pin/unpin, transition/recovery status, and transient playback warnings are all user-facing. Remaining acceptance is physical-device QA. |

## Remaining Add Plan

| Phase | Goal | Add |
|---|---|---|
| 5 | Add shared session UI only after adapter exists | Build real SharePlay/GroupActivities adapter first, then add invite/start, participant presence, lobby readiness, shared queue reconciliation, and action attribution. |
| 6 | Add durable media features where product scope demands them | Add video offline downloads, audio EQ/effects, live visualizer, durable queue/history, playlist persistence, and consolidated media settings only when their backing services are composed. |
| 7 | Add immersive/multiview only as product scope | Expose immersive/spatial badges and host handoff for supported content; add multiview controls only when there is an actual multiview product flow. |

## Non-Negotiable Product Rules

| Rule | Reason |
|---|---|
| Do not show dead controls in production. | The existing wireframes have disabled buttons for useful planning, but the shipped product should not tease fake doors. |
| Do not expose raw resolved media URLs to normal users. | URL fields are demo scaffolding. Production flows should start from library/detail media identity. |
| Do not imply custom audio engine Spatial Audio. | Spatial policy currently belongs to the `AVQueuePlayer` system route and platform route settings. |
| Do not imply inline custom-layer video is full immersive playback. | `PlayerContainerView` is honest 2D/custom-layer playback; immersive content needs host-owned AVKit/Quick Look/RealityKit handoff. |
| Do not publish Now Playing for previews, placeholders, chimes, notifications, or silent keepalives. | System playback metadata is a long-form media signal and affects routes, AirPods, and remote controls. |
| Do not add shared-session controls before shared queue/session identity is real. | Synchronized time without synchronized media identity creates misleading shared playback. |
| Keep URL resolution out of views. | Use `URLResolver` for deterministic normalization and `GatewayFallbackChain` only where reachability probing is genuinely needed. |
| Register accessibility identifiers before shipping new flows. | Primary controls, empty states, errors, and destructive confirmations must live in the AuraUI A11y registry. |

## Implementation Backlog

| Priority | Item | Target Area | Depends On |
|---|---|---|---|
| P0 | Run release-device AuraPlay media QA | Audio/video | Real hardware coverage for Lock Screen, Control Center, AirPlay, AirPods, interruptions, background/foreground restore, poor-network buffering, gapless playback, and battery |
| P1 | Add video offline download controls | Video | Manifest store and download managers composed in app |
| P1 | Wire AirPlay optimized audio route | Audio | Explicit route handoff design, queue/position transfer, and QA |
| P2 | Extend poster fallback to detail/Now Playing | Video | Poster generation already composed and used in library rows |
| P1 | Surface gateway fallback recovering status in UI | Video | `VideoGatewayResolving` adapter already composed; fallback currently reads as buffering |
| P2 | Add media storage quota controls | Audio/video | Product decision on global offline storage management |
| P2 | Add playlists and durable history | Library/playback | Persistence models/services |
| P3 | Add shared session launch/presence/lobby | MediaCore/shared | Real GroupActivities adapter |
| P3 | Add action attribution banners | MediaCore/shared | Shared session event stream |
| P4 | Add immersive/multiview UI | Video | Product scope and host presentation adapters |

## Verification Needed After Implementation

| Area | Verification |
|---|---|
| App shell | Cold start, restore saved account, launch without saved account, limited-storage warning, scene active refresh, malformed deep link, valid deep link before shell readiness, route-error dismissal. |
| Onboarding/accounts | Manual address entry, ENS resolution, stale/changed ENS mapping, paste, QR camera permission allow/deny, guest pass activation, account switch, chain switch, account removal, privacy reset return-to-gateway. |
| Global chrome/navigation | Account switcher, context inspector, Search auxiliary surface, Receipts/NFT/ERC-20 auxiliary surfaces in release visibility, tab switching, back/pop behavior, mini-player placement. |
| Home | Sparse account, populated account, generated artwork available/unavailable, image preview, pinned actions, launcher routes, recent activity, logout, Dynamic Type and Reduce Transparency. |
| News/NFT tokens | Feed refresh, cached provider failure, uncached provider failure, empty library, NFT detail, collection detail, external link confirmation, receipt-write warning/error paths. |
| ERC-20/Gas | Token sync success/warning/error, persistence error retry, empty holdings, token detail, offline/cached gas, live gas refresh, provider timeout, unsupported/limited chain behavior. |
| Search/Settings/Profile | Search history save/delete/clear errors, invalid input safety copy, result routing, settings privacy reset success/error, provider config diagnostics, profile asset count refresh, observe-mode denial. |
| Audio playback | Xcode build, focused MusicFeature tests, real-device playback, interruptions, background audio, Lock Screen controls, AirPlay route picker. |
| Audio offline | Download progress, cancellation, offline launch, pinned item eviction behavior, stale source invalidation. |
| Audio visualization/effects | Reduce Motion behavior, CPU/battery check, no graph leaks after leaving Now Playing. |
| Video playback | Inline playback, buffering, seek, speed, errors, AirPlay, PiP, fullscreen, phone interruption, background/restore. |
| Video offline | Progressive MP4 download, HLS package download, offline playback, cancellation, failed retry, local-file reuse. |
| Video media features | Captions, audio descriptions, audio variants, chapters, HDR badge, poster fallback, portrait/square/landscape layout. |
| Shared sessions | Real SharePlay launch, participant lifecycle, late join, queue reconciliation, action attribution, PiP on coordinated background. |
| Accessibility | Dynamic Type, VoiceOver labels/values/hints, accessible identifiers, Reduce Motion, button target sizes, non-color-only status. |

## Bottom Line

This report now covers both AuraPlay and the surrounding Auralis app surfaces at a static audit level. The broader app is not empty or merely scaffolded: shell restoration, Home, Search, Gas, profile/settings, NFT browsing, ERC-20 holdings, account switching, and onboarding all have meaningful UI. The main app-level gaps are runtime QA, documented release-vs-debug visibility, large-data/large-text verification, provider/offline failure coverage, and a few accessibility identifier hardening items.

The required AuraPlay UI is now implemented for the scoped 2D audio/video release path: audio playback has system metadata, remote commands, queue/recent playback, route picker, and active-track offline controls; video playback opens wallet-scoped media items with production transport, PiP, fullscreen, route, track, chapter, and resume controls; the root library has search, sort, and filters.

Consumption status: ready as an implementation-backed requirements record after build verification. It is not a completed hardware QA sign-off, accessibility certification, shared-session release, video-offline release, or immersive/multiview release.
