# AuraPlayMediaCore

Shared, dependency-free contracts for the AuraPlay media packages. Playable media identity, cache state, download primitives, playback ticks, and common media errors live here so `AuraPlayAudioEngine` and `AuraPlayVideoEngine` don't need two labels for the same ingredients.

The dependency direction is one-way: the app, features, and both engines may depend on this package; this package depends on nothing but Foundation and CryptoKit.

## Contents

| Area | Files | What it provides |
| --- | --- | --- |
| Media identity | `AuraPlayableMedia.swift`, `MediaMetadata.swift` | `AuraPlayableMedia` protocol, content kind, cached-file state, type erasure, now-playing metadata |
| Caching | `MediaCacheContracts.swift`, `MediaOfflineState.swift` | `MediaCacheManaging` contract, collision-resistant `CacheKey`, cache progress and loudness events, offline download lifecycle |
| Downloading | `MediaDownloading.swift` | `URLSessionMediaDownloader` with full, resumable, and progressive (playable-before-complete) downloads, backpressured chunk streaming |
| URL resolution | `MediaURLResolving.swift` | `ipfs://` / `ar://` gateway mapping with query and fragment preservation, ordered gateway fallback |
| Playback integration | `RemotePlaybackContracts.swift`, `MediaSessionContracts.swift`, `PlaybackTick.swift` | Transport control, remote-command dispatch, now-playing publishing, audio-session events |
| SharePlay vocabulary | `SharedMediaSessionContracts.swift` | Neutral GroupActivities-shaped session/activity/queue identity consumed by the video engine's integration surface |
| Support | `AuraPlayError.swift`, `MediaNetworkStatus.swift`, `MediaEngineLogging.swift` | Shared errors, network status, logging contracts |

## Notes for implementers

- `AuraPlayError.errorDescription` strings are currently English-only; map to app-localized strings before surfacing in UI.
- `MediaCacheManaging`'s `progress`/`loudnessMeasurements` must return a fresh, independent stream on every access (streams are single-consumer; no replay for late subscribers).
- `AnyAuraPlayableMedia` stringifies IDs via `String(describing:)`; namespace IDs when mixing ID types in one collection.

## Testing

Run the package tests with `swift test` from this directory (requires a full Xcode toolchain — Command Line Tools alone lack Testing.framework). The auto-generated Xcode scheme for this package has an empty test plan, so the CLI is the reliable route.
