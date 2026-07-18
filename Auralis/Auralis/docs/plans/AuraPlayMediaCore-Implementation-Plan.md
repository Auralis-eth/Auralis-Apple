# AuraPlayMediaCore Implementation Plan

## Goal

Create `AuraPlayMediaCore` as the neutral shared package for media contracts used by `AuraPlayAudioEngine` and `AuraPlayVideoEngine`.

The boundary should stay boring on purpose: value types, protocols, and shared errors only. Audio decoding, AVAudioEngine graph work, AVPlayer orchestration, SwiftUI/UIKit views, and platform-specific session managers remain in the concrete engine packages.

## Architecture Fit

Pattern: Clean Architecture package boundary.

Fit: this is a module-boundary refactor, not a screen-state problem. `AuraPlayMediaCore` becomes the domain contract layer, while audio/video packages remain infrastructure adapters that implement playback behavior.

## Phase 1: Create The Core Package

- Add `AuraPlayMediaCore/Package.swift` with Swift tools 6.0 and the same platform floor used by the engine packages.
- Move generic playable-media contracts into core:
  - `AuraPlayableMedia`
  - `AuraPlayableContentKind`
  - `AuraCachedFileState`
  - `AnyAuraPlayableMedia`
- Move common error and cache contracts into core:
  - `AuraPlayError`
  - `CachedLoudnessMeasurement`
  - `CacheProgress`
  - `MediaCacheManaging`
  - `CacheKey`
- Move shared playback progress into core:
  - `PlaybackTick`

## Phase 2: Source-Compatible Engine Adoption

- Add `.package(path: "../AuraPlayMediaCore")` to `AuraPlayAudioEngine` and `AuraPlayVideoEngine`.
- Add target dependencies on `AuraPlayMediaCore`.
- Replace duplicated declarations in the existing packages with public typealiases/re-exports.
- Keep old public names available through the engine packages during the transition.

## Phase 3: Deeper Migration

- Completed shared migrations:
  - remote command models
  - now-playing state and snapshot contracts
  - generic now-playing publishing contracts
  - media-session/interruption events and neutral session-management protocol
  - gateway URL resolving protocol and default IPFS/Arweave resolver
  - generic media metadata
  - shared playable media plus metadata adapter (`AuraPlayableMediaItem`), with video playable media now built on `AuraPlayableMedia`
  - generic downloading contracts (`MediaDownloading`, progressive/resumable download protocols, and `ProgressiveMediaDownloadHandle`)
  - shared network availability contract (`MediaNetworkStatusProviding`) and always-online fixture/default provider
  - neutral offline download state (`MediaOfflineState`) with video retaining `VideoOfflineDownloadState` as a compatibility alias
  - generic media-engine logging contract (`MediaEngineLogging`) and no-op logger
- Kept engine-specific:
  - AVFoundation/AVKit concrete publishers and session managers
  - audio cache manager, URLSession downloader implementation, loudness measurement, and audio validation
  - video resource loaders, offline/progressive cache stores and records, PiP, immersive handoff, subtitle/audio-description tracks, seek tolerance, presentation analysis, and queue controller internals
- Still worth auditing later:
  - offline/progressive cache record shapes once video and audio prove they need the same persistence contract
  - a stricter shared URI resolver if `MusicFeature` storage resolution becomes an engine dependency rather than feature-level URL preparation

## Validation

- Passed after generic contract migration: `DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer xcrun swift test --disable-sandbox --scratch-path /private/tmp/auralis-mediacore-build` in `AuraPlayMediaCore` with 8 tests.
- Passed after generic contract migration: `DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer xcrun swift build --disable-sandbox --scratch-path /private/tmp/auralis-audioengine-build --target AuraPlayAudioEngine` in `AuraPlayAudioEngine`.
- Passed after generic contract migration: `DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer xcrun swift build --disable-sandbox --scratch-path /private/tmp/auralis-videoengine-build --target AuraPlayVideoEngine` in `AuraPlayVideoEngine`.
- Passed: `DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer xcrun swift test --disable-sandbox --scratch-path /private/tmp/auralis-mediacore-build` in `AuraPlayMediaCore`.
- Passed: `DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer xcrun swift build --disable-sandbox --scratch-path /private/tmp/auralis-audioengine-build --target AuraPlayAudioEngine` in `AuraPlayAudioEngine`.
- Passed: `DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer xcrun swift build --disable-sandbox --scratch-path /private/tmp/auralis-videoengine-build --target AuraPlayVideoEngine` in `AuraPlayVideoEngine`.
- Passed after playable-media adapter migration: `DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer xcrun swift test --disable-sandbox --scratch-path /private/tmp/auralis-mediacore-build` in `AuraPlayMediaCore` with 5 tests.
- Passed after playable-media adapter migration: `DEVELOPER_DIR=/Users/danielbell/Downloads/Xcode-beta.app/Contents/Developer xcrun swift build --disable-sandbox --scratch-path /private/tmp/auralis-videoengine-build --target AuraPlayVideoEngine` in `AuraPlayVideoEngine`.
- Blocked: full package tests for engine packages because the demo SwiftUI executable cannot load `SwiftUIMacros.StateMacro` through the local plugin server in this environment.
- Blocked: `Auralis` scheme build because DerivedData/module-cache writes fail with `No space left on device`.
- Blocked after playable-media adapter migration: `AuraPlayAudioEngine` rebuild could not complete because Swift build/index files under `/private/tmp/auralis-audioengine-build` failed with `No space left on device`.
