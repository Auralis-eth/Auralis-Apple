# AuraPlayVideoEngine

`AuraPlayVideoEngine` is AuraPlay's standalone Swift package for video playback. It owns AVFoundation playback, async asset loading, custom video presentation, playback observation, progressive play-while-downloading cache support, offline download state, PiP/AirPlay seams, media-track inspection, and host-app integration protocols.

This package is playback infrastructure. It deliberately does not implement video editing, effects, or export.

## Current Scope

Implemented:

- AVPlayer-based playback through `VideoPlayerController`.
- One custom `AVPlayerLayer` surface through `PlayerContainerView`; SwiftUI `VideoPlayer` and `AVPlayerViewController` are not used.
- Async `AVURLAsset` construction and preload plans through `VideoAssetLoader`.
- Player-item buffering policy through `VideoBufferingPolicy` and `preferredForwardBufferDuration`.
- Playback events as `AsyncStream<VideoPlaybackEvent>`.
- 60fps periodic progress ticks with idempotent observer cleanup.
- Smooth seek coalescing through `ChaseTimeSeekCoordinator`.
- Playback queue advancement through `VideoPlaybackQueueController`.
- Subtitle, audio-description, audio-variant, chapter, HDR, high-frame-rate, spatial-video, and pixel-buffer-output helper APIs.
- PiP and AirPlay route-picker integration seams.
- Now Playing, remote commands, media-session, gateway fallback, artwork cache, and playback-position protocols for host-app adapters.
- Progressive MP4/MOV play-while-downloading through `ProgressiveVideoCachingPipeline`.
- Offline progressive downloads through `ProgressiveVideoOfflineDownloadManager`.
- Offline HLS package downloads through `HLSVideoOfflineDownloadManager`.
- Offline/local playback lookup through `VideoOfflineManifestStore`.

Not implemented by design:

- `AVMutableComposition` editing timelines.
- `AVMutableVideoComposition` effects, Core Image/Metal/Vision processing, filters, color grading, overlays, transitions, or speed ramps.
- `AVAssetExportSession` export.
- Full DRM/FairPlay key management with `AVContentKeySession` or persistent offline keys.
- App entitlements/background-mode configuration; the host app owns capabilities.

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
  Host-app boundary protocols. Keep app-specific gateway, queue, receipt, Now Playing, remote command, artwork, and persistence code outside this package.
- `VideoPlaybackIntegrationCoordinator.swift`
  Wires player events to host adapters: persistence, Now Playing, remote commands, media-session events, gateway fallback, and completion.
- `VideoMediaTrackManager.swift`
  Audio variants, chapters, capabilities, high-frame-rate/spatial-video checks, and `AVPlayerItemVideoOutput` helper.
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

Progressive play-while-downloading:

1. Host creates `ProgressiveVideoCachingPipeline` and passes it to `VideoPlayerController` or `VideoAssetLoader`.
2. Eligible progressive HTTPS URLs are rewritten to the custom scheme, default `auraplay-video-cache://`.
3. AVFoundation sends byte-range requests to `ProgressiveVideoResourceLoader`.
4. Cached ranges are served immediately from `ProgressiveVideoCacheStore` when available.
5. Missing ranges are fetched with `URLSession.bytes(for:)` and streamed to AVFoundation in chunks while also being written to disk.
6. `didCancel` cancels the per-request streaming task and removes it from the active task registry.
7. When cached byte ranges cover the full content length, `ProgressiveVideoCacheStore.localFileURL(for:)` becomes available.

Offline downloads:

- Progressive MP4/MOV: use `ProgressiveVideoOfflineDownloadManager`, which wraps a background `URLSessionDownloadTask` and records state in `VideoOfflineManifestStore`.
- HLS `.m3u8`: use `HLSVideoOfflineDownloadManager`, which wraps `AVAssetDownloadURLSession` and records the resulting local package URL in `VideoOfflineManifestStore`.
- Playback reuse: `VideoAssetLoader` prefers manifest records whose state is `.available` and loads the local file URL before trying network playback.

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
let progressiveDownloader = ProgressiveVideoOfflineDownloadManager(manifestStore: manifestStore)
try await progressiveDownloader.startDownload(for: URL(string: "https://cdn.example/video.mp4")!)

for await record in await progressiveDownloader.downloadProgress(for: sourceURL) {
    print(record.state, record.progress)
}
```

```swift
let hlsDownloader = HLSVideoOfflineDownloadManager(manifestStore: manifestStore)
try await hlsDownloader.startDownload(for: URL(string: "https://cdn.example/master.m3u8")!)
```

## Media Adapter Contract

The engine does not import app-specific NFT or queue types. Host objects can conform to:

```swift
public protocol VideoPlayableMedia: Sendable {
    var videoMediaID: String { get }
    var videoTitle: String { get }
    var videoArtist: String? { get }
    var videoArtworkURL: URL? { get }
    var resolvedPlaybackURL: URL { get }
}
```

`VideoPlayerController.load(media:)` validates and loads `resolvedPlaybackURL`. `VideoMediaMetadata(media:)` maps the same object into Now Playing metadata.

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

The demo expects a resolved HTTPS MP4/MOV/HLS URL. It does not resolve NFT gateway URLs itself.

## Production QA Still Required

CI can validate policy and coordination logic, but real media behavior still needs device QA:

- Progressive resource loading under scrubbing, cancellation, server range quirks, and network failure.
- Background progressive download through app suspension/resume.
- HLS offline package download and offline playback.
- Memory pressure with large media files.
- PiP, AirPlay, route picker, interruptions, Lock Screen Now Playing, and HDR output.
- Host app background modes and entitlements.
