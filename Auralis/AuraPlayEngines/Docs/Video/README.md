# AuraPlayVideoEngine

`AuraPlayVideoEngine` is AuraPlay's standalone Swift package for video playback. It owns AVFoundation playback, async asset loading, custom video presentation, playback observation, progressive play-while-downloading cache support, offline download state, PiP/AirPlay seams, media-track inspection, and host-app integration protocols.

This package is playback infrastructure. It deliberately does not implement video editing, effects, or export.

## Current Scope

Implemented:

- AVPlayer-based playback through `VideoPlayerController`.
- One custom `AVPlayerLayer` surface through `PlayerContainerView`; SwiftUI `VideoPlayer` and concrete `AVPlayerViewController` ownership are not used.
- Async `AVURLAsset` construction and preload plans through `VideoAssetLoader`.
- Player-item buffering policy through `VideoBufferingPolicy` and `preferredForwardBufferDuration`.
- Playback events as `AsyncStream<VideoPlaybackEvent>`.
- 60fps periodic progress ticks with idempotent observer cleanup.
- Smooth seek coalescing through `ChaseTimeSeekCoordinator`.
- Playback queue advancement through `VideoPlaybackQueueController`.
- Subtitle, audio-description, audio-variant, chapter, HDR, high-frame-rate, immersive media profile detection, immersive playback policy, and pixel-buffer-output helper APIs.
- PiP and AirPlay route-picker integration seams.
- Multiview coordination through `VideoMultiviewCoordinator` for synchronized participants, route preference, non-mixable audio preference, and per-player network priority hints.
- Now Playing, remote commands, media-session, gateway fallback, AVKit immersive handoff, artwork cache, and playback-position protocols for host-app adapters.
- Progressive MP4/MOV play-while-downloading through `ProgressiveVideoCachingPipeline`.
- Offline progressive downloads through `ProgressiveVideoOfflineDownloadManager`.
- Offline HLS package downloads through `HLSVideoOfflineDownloadManager`.
- Offline/local playback lookup through `VideoOfflineManifestStore`.

Not implemented by design:

- `AVMutableComposition` editing timelines.
- `AVMutableVideoComposition` effects, Core Image/Metal/Vision processing, filters, color grading, overlays, transitions, or speed ramps.
- `AVAssetExportSession` export.
- Full DRM/FairPlay key management with `AVContentKeySession` or persistent offline keys.
- Live immersive production ingest, SMPTE 2110 transport, ProRes/ASAF/MEBX recording, replay playout, or `AVAssetWriter` export tooling.
- visionOS custom environment ownership, including `ImmersiveSpace` scenes, Reality Composer Pro docking regions, media reflections, environment probes, passthrough tint/brightness, reverb presets, immersive environment picker entries, or SharePlay environment synchronization.
- App entitlements/background-mode configuration; the host app owns capabilities.

Platform note: macOS consumers get playback, asset loading, caching, and policy APIs. `PictureInPictureController` and `VideoRoutePickerView` are functional on iOS-family platforms only and compile to inert stubs on macOS; AVKit's macOS PiP and route picker are not wired up.

## Architecture Map For LLMs

Start here when reasoning about the package:

- `VideoPlayerController.swift`
  Main playback controller. Owns `AVPlayer`, state transitions, KVO, time observer registration, seek calls, item replacement, speed restore, and teardown.
- `VideoAssetLoader.swift`
  Asset/item construction, preload keys, offline manifest lookup, offline download records/managers, progressive background downloads, and HLS package downloads.
- `VideoResourceLoaderCoordinator.swift`
  Generic resource-loader coordinator plus progressive cache URL rewriting, sparse byte-range cache, streaming resource-loader bridge, cancellation cleanup, and local cache reuse.
- `PlayerContainerView.swift`
  SwiftUI/AppKit/UIKit bridge for the raw `AVPlayerLayer` surface. Dismantle detaches the player.
- `IntegrationProtocols.swift`
  Host-app boundary protocols. Keep app-specific gateway, queue, receipt, Now Playing, remote command, AVKit immersive presentation, artwork, and persistence code outside this package.
- `VideoPlaybackIntegrationCoordinator.swift`
  Wires player events to host adapters: persistence, Now Playing, remote commands, media-session events, gateway fallback, and completion.
- `VideoMediaTrackManager.swift`
  Audio variants, chapters, capabilities, high-frame-rate checks, `AVAssetPlaybackAssistant` immersive profile detection, and `AVPlayerItemVideoOutput` helper.
- `VideoMultiviewCoordinator.swift`
  Multi-player orchestration for synchronized or independent participants, AirPlay/external-route preference, non-mixable audio preference, and network-resource priority hints.
- `VideoSpatialPlaybackPolicy.swift`
  Pure policy mapping that describes what each playback surface can honestly provide for 2D, stereo, spatial, Apple Projected Media Profile, and Apple Immersive Video assets.
- `SubtitleTrackManager.swift`
  Legible and audio-description media-selection helpers.
- `PictureInPictureController.swift` and `RoutePickerView.swift`
  System video integrations.
- `Tests/AuraPlayVideoEngineTests/VideoEngineCoreTests.swift`
  Swift Testing coverage for policy, loading, observation, cache state, queueing, integrations, and teardown.

## Core Data Flow

Normal playback:

1. Host app resolves any `ipfs://`, `ar://`, NFT gateway, or signed URL into an HTTPS media URL.
2. Host object conforms to `VideoPlayableMedia`, or calls `VideoPlayerController.load(resolvedURL:)` directly.
3. `VideoFormatValidator` rejects unresolved URLs and WebM.
4. `VideoAssetLoader` checks `VideoOfflineManifestStore` for an available local file.
5. If no local file exists, `VideoAssetLoader` creates an `AVURLAsset`, optionally through `ProgressiveVideoCachingPipeline`.
6. `VideoPlayerController` replaces the current item, observes item/player state, and emits `VideoPlaybackEvent` values.
7. Host adapters receive events through `VideoPlaybackIntegrationCoordinator`.

Queue advancement: `VideoPlaybackQueueController` loads each next item's resolved URL directly on the controller. It intentionally bypasses `VideoPlaybackIntegrationCoordinator.load(media:)`, so per-item media-session configuration and stored-position restore do not run automatically. Hosts that want those semantics per queue item should observe the queue's `.advanced` events and load through their integration coordinator.

Progressive play-while-downloading:

1. Host creates `ProgressiveVideoCachingPipeline` and passes it to `VideoPlayerController` or `VideoAssetLoader`.
2. HTTPS URLs with a known progressive file extension (default `mp4`, `m4v`, `mov`, configurable through `ProgressiveVideoCacheConfiguration.progressiveFileExtensions`) are rewritten to the custom scheme, default `auraplay-video-cache://`. Other URLs, including extensionless gateway URLs and HLS playlists, play directly without progressive caching.
3. AVFoundation sends byte-range requests to `ProgressiveVideoResourceLoader`.
4. Cached ranges are served immediately from `ProgressiveVideoCacheStore` when available.
5. Missing ranges are fetched with `URLSession.bytes(for:)` and streamed to AVFoundation in chunks while also being written to disk.
6. Servers that ignore the Range header and reply 200 stream from byte zero; the loader caches from zero, forwards only the requested window to AVFoundation, and cancels the transfer once the window is served, instead of failing playback.
7. `didCancel` cancels the per-request streaming task and removes it from the active task registry.
8. When cached byte ranges cover the full content length, `ProgressiveVideoCacheStore.localFileURL(for:)` becomes available. That URL is cache inspection only — keep loading through the original HTTPS URL, which the pipeline then serves from the local cache.
9. `ProgressiveVideoCacheConfiguration.maxCacheBytes` caps the disk cache, defaulting to 2 GB. The store evicts older entries when an entry finishes or after every 32 MB written, keeping the entry currently being written. If the system purges cached files, reads degrade to a cache miss and the missing ranges are refetched from the network.

Offline downloads:

- Progressive MP4/MOV: use `ProgressiveVideoOfflineDownloadManager`, which wraps a background `URLSessionDownloadTask` and records state in `VideoOfflineManifestStore`.
- HLS `.m3u8`: use `HLSVideoOfflineDownloadManager`, which wraps `AVAssetDownloadURLSession` and records the resulting local package URL in `VideoOfflineManifestStore`.
- Playback reuse: `VideoAssetLoader` prefers manifest records whose state is `.available` and loads the local file URL before trying network playback. If the local file no longer exists, loading falls back to the network URL.
- Progressive download files are excluded from iCloud/device backups because they are re-fetchable media.
- Duplicate `startDownload(for:)` calls for an already-active source URL are ignored so concurrent tasks do not write to the same destination.
- Store initializers do not synchronously load manifests. Disk reads are deferred until the actor receives its first operation.

## Public API Sketch

```swift
let manifestStore = VideoOfflineManifestStore()
let cachePipeline = ProgressiveVideoCachingPipeline()
let controller = VideoPlayerController(
    progressiveCachingPipeline: cachePipeline,
    offlineManifestStore: manifestStore
)

try await controller.load(resolvedURL: URL(string: "https://cdn.example/video.mp4")!)
controller.play()
```

```swift
let progressiveDownloader = ProgressiveVideoOfflineDownloadManager(
    manifestStore: manifestStore,
    backgroundSessionIdentifier: "com.example.app.video.offline.progressive"
)
try await progressiveDownloader.startDownload(for: URL(string: "https://cdn.example/video.mp4")!)

for await record in await progressiveDownloader.downloadProgress(for: sourceURL) {
    print(record.state, record.progress)
}
```

```swift
let hlsDownloader = HLSVideoOfflineDownloadManager(
    manifestStore: manifestStore,
    backgroundSessionIdentifier: "com.example.app.video.offline.hls"
)
try await hlsDownloader.startDownload(for: URL(string: "https://cdn.example/master.m3u8")!)
```

Use one live download manager per background session identifier, and choose identifiers that are stable across launches so the host app can reattach to system-owned background work.

When the app delegate receives `handleEventsForBackgroundURLSession`, pass the identifier and completion handler to the matching download manager with `handleEventsForBackgroundURLSession(identifier:completionHandler:)`. The manager calls the completion handler from `urlSessionDidFinishEvents(forBackgroundURLSession:)` after the system has delivered pending background events.

PiP background behavior depends on AVKit's automatic inline PiP transition. `PictureInPictureController` enables `canStartPictureInPictureAutomaticallyFromInline`; hosts should not rely on manually calling `startPictureInPicture()` after the app has already entered the background.

`PlayerContainerView.onLayerReady` runs during view creation and SwiftUI/AppKit updates. Hosts that create PiP controllers from that callback should cache/reuse the controller for the supplied layer instead of creating a fresh controller every update.

## Media Adapter Contract

The engine does not import app-specific NFT or queue types. `VideoPlayableMedia` refines `AuraPlayableMedia` from `AuraPlayMediaCore` (re-exported by this package):

```swift
public protocol VideoPlayableMedia: AuraPlayableMedia {
    var mediaMetadata: MediaMetadata { get }
}
```

Conforming types supply the `AuraPlayableMedia` requirements (`id`, `sourceURL`, `declaredFormat`, `contentKind`, `cachedFileState`, `approxLoudnessLUFS`) plus `mediaMetadata`. Protocol extensions derive the video-facing accessors from those: `videoMediaID`, `videoTitle`, `videoArtist`, `videoArtworkURL`, and `resolvedPlaybackURL` (the `sourceURL`). `AuraPlayableMediaItem` already conforms, so hosts can pass the shared core media item directly.

`VideoPlayerController.load(media:)` validates and loads `resolvedPlaybackURL`. `VideoMediaMetadata(media:)` maps the same object into Now Playing metadata.

## Playback Event Stream Contract

`VideoPlayerController.events` is a bounded `AsyncStream` that keeps the newest events. This prevents 60fps tick events from accumulating forever when a host creates a controller but does not consume events.

Each access to `controller.events` returns an independent stream, so multiple observers — for example `VideoPlaybackIntegrationCoordinator` and `VideoPlaybackQueueController` wired to the same controller — each receive every event. Events emitted before a stream is created are not replayed to late subscribers. `VideoPlaybackIntegrationCoordinator.startObserving(observesPlaybackEvents: false)` remains available when a host wants another component to be the only playback-event consumer.

## Package Layout

- `Sources/AuraPlayVideoEngine/`
  Library target with playback, asset loading, cache/offline, presentation, media-track, and integration code.
- `Examples/AuraPlayVideoEngineDemo/`
  Small SwiftUI executable harness for loading an already-resolved HTTPS video URL.
- `Tests/AuraPlayVideoEngineTests/`
  Swift Testing coverage for pure policy, presentation, persistence, cache state, and seek/coordinator behavior.
- `docs/decisions/`
  ADRs for streaming/cache and custom player surface decisions.
- `docs/release/`
  Manual QA checklist for device-only AVFoundation behavior.

## Build And Test

Open the package in Xcode or select the package scheme from the workspace.

From the package parent:

```sh
swift test --package-path AuraPlayVideoEngine
swift run --package-path AuraPlayVideoEngine AuraPlayVideoEngineDemo
```

`swift test` requires the full Xcode toolchain. The Command Line Tools toolchain cannot compile the demo target's SwiftUI `@State` macro; if `xcode-select -p` points at CommandLineTools, run with `DEVELOPER_DIR` set to your Xcode installation.

To run the suite on an iOS simulator (the shared `AuraPlayVideoEngine` scheme carries the test action), run from the package directory:

```sh
xcodebuild test -scheme AuraPlayVideoEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

CI should run one of these two commands; the app's Xcode test plans do not include this package's tests.

The demo expects a resolved HTTPS MP4/MOV/HLS URL. It does not resolve NFT gateway URLs itself.

## Production QA Still Required

CI can validate policy and coordination logic, but real media behavior still needs device QA:

- Progressive resource loading under scrubbing, cancellation, server range quirks, and network failure.
- Background progressive download through app suspension/resume.
- HLS offline package download and offline playback.
- Memory pressure with large media files.
- PiP, AirPlay, route picker, interruptions, Lock Screen Now Playing, and HDR output.
- Multiview sync, route arbitration, and quality behavior with real concurrent streams and external routes.
- visionOS host-app theater environments: AVKit fullscreen docking, custom docking-region comfort, media reflections, reverb, tint/brightness, immersive environment picker discovery, and SharePlay environment sync.
- Host app background modes and entitlements.
