# AuraPlayAudioEngine

`AuraPlayAudioEngine` is the local Swift Package Manager package for AuraPlay playback infrastructure.

It is a generic playback engine package. App models such as `NFT` adapt into `AuraPlayableMedia`; this package does not import the app's NFT, SwiftData, wallet, or routing types.

## LLM Orientation

If you are using this repository as context, start here:

- This package owns playback infrastructure, not app navigation or SwiftData persistence.
- The active model is download-then-play with progressive local-file readiness. It does not stream remote audio directly through `AVAudioEngine`.
- The main app should adapt its media models into `AuraPlayableMedia` values and persist cache/loudness state itself.
- Do not add an audio export pipeline unless there is a product requirement to save edited or processed audio files.
- Visualizers and analysis output should be added as a side-channel from the playback graph, not as exported audio.
- Publish Now Playing only for real long-form media playback; do not use AuraPlay or Now Playing for previews, chimes, notification sounds, placeholders, or silent keepalives.

## Current Status

Phase 6 implementation is in place at the package-infrastructure level:

- live `AudioSessionManager` with route/interruption event stream
- `MediaCacheManager` actor for download-then-play local caching, progressive playable-file return, persisted ranged partial resume, pinning, reuse, and LRU eviction
- `AudioEngineController` with live graph introspection for the v1 graph: primary player + prebuffer player -> track mixer -> EQ -> Apple dynamics processor -> main mixer
- `GaplessScheduler` cached-track preparation, render-frame boundary planning for prepared transitions, bounded brief-gap fallback, bounded read-ahead buffer scheduling, and format conversion
- `AutoMixController` equal-power crossfade planning with ramp progress driven from rendered frame position rather than elapsed wall-clock time
- `EngineRecoveryCoordinator` for interruption/configuration recovery events, progressive underrun pause/reschedule/recovery, current-file rescheduling, and watchdog retries
- native `AVAudioFile` track-source validation with decoder-plugin extension point, embedded MP3/FLAC fixture coverage, and generated AAC/ALAC fixture coverage
- EQ preset math, Apple dynamics parameters, RMS approximate loudness measurement, and cache-completion loudness measurement events for app persistence
- live RMS/peak visualization frames from the playback graph for meters, waveforms, and lightweight visualizers
- Now Playing and remote command publishers with artwork snapshots, elapsed-time ticking, and command-target cleanup
- `AirPlayQueuePlayerController`, an opt-in `AVQueuePlayer` route for AirPlay/HomePod/Apple TV/wireless CarPlay playback where enhanced system buffering matters more than AuraPlay's custom graph
- Swift Testing coverage for core pure logic, generated native container validation, progressive cache readiness, bounded read-ahead scheduling, gapless transition arming plus boundary planning, cache validation/reuse, format dispatch, live graph topology, dynamics parameters, loudness measurement handoff, Now Playing timing, system command interval configuration, and the AirPlay-optimized queue contract

Physical-device QA remains the release gate for route changes, interruptions, background playback, Lock Screen controls, accessory controls, audible gaplessness, and battery behavior.

## Host Integration Gates

The package is not a complete shipping playback experience until the host app completes these integration gates:

- Wire `AuraPlayAudioEngine` into real playback flows, including real queue state, user controls, route selection, cache persistence, and app-owned media adapters.
- Set the host app Info.plist `AVInitialRouteSharingPolicy` key to `LongFormAudio` using Xcode's **AirPlay optimization policy** setting.
- Enforce Now Playing discipline: publish Now Playing only for real long-form media playback, never for chimes, previews, placeholders, onboarding sounds, notification sounds, or silent keepalives.

Spatial Audio and Press to Mute are complete for Phase 6 as explicit boundaries, not runtime playback features. Spatial Audio starts with the `AVQueuePlayer` system route in a future phase. Press to Mute and voice processing belong to a future microphone/call/live-room feature, not this playback package.

## Package Layout

- `Sources/AuraPlayAudioEngine/`
  Public engine contracts and implementation.
- `Tests/AuraPlayAudioEngineTests/`
  Swift Testing unit tests for pure logic and package behavior.
- `Examples/AuraPlayAudioEngineDemo/`
  A SwiftUI demo executable scaffold.
- `Docs/Phase6ImplementationPlan.md`
  Ticket landing order and package boundary guidance.
- `Docs/ADR-003-Download-Then-Play.md`
  The Phase 6 download-then-play architecture decision.
- `Docs/QA/Phase6DeviceManualChecklist.md`
  Manual device QA gate for behavior CI cannot synthesize.

## Build And Test

Open the package in Xcode or select the package's demo executable from the workspace after Xcode refreshes package discovery.

From the command line:

```sh
swift test --package-path AuraPlayAudioEngine
swift run --package-path AuraPlayAudioEngine AuraPlayAudioEngineDemo
```

## Minimal Playback Example

This is the smallest useful shape for host-app playback. The host app supplies a media value, asks the cache for a playable local file, schedules it, and starts the engine.

```swift
import AuraPlayAudioEngine
import Foundation

struct AppTrack: AuraPlayableMedia {
    let id: String
    let sourceURL: URL
    let declaredFormat: String?
    let contentKind: AuraPlayableContentKind
    let cachedFileState: AuraCachedFileState
    let approxLoudnessLUFS: Double?
}

func play(track: AppTrack) async throws {
    let cache = try MediaCacheManager()
    let engine = try AudioEngineController()
    let scheduler = GaplessScheduler(cacheManager: cache, engineController: engine)

    let localURL = try await cache.localFileWhenPlayable(
        for: track,
        minimumPlayableBytes: 512_000
    )

    await engine.configureForContentKind(track.contentKind)
    await engine.applyNormalizationGain(approxLoudnessLUFS: track.approxLoudnessLUFS)
    try await scheduler.scheduleCurrent(fileURL: localURL, startingFrame: 0)
    try await engine.start()
}
```

In a real app, keep `MediaCacheManager`, `AudioEngineController`, and `GaplessScheduler` alive for the lifetime of the player instead of recreating them for each track.

## NFT Adapter Direction

Keep the adapter in the app target:

```swift
struct NFTPlayableMedia: AuraPlayableMedia {
    let nft: NFT

    var id: String { nft.id }
    var sourceURL: URL { nft.audioURL }
    var declaredFormat: String? { nft.mediaFormat }
    var contentKind: AuraPlayableContentKind { nft.isSpokenWord ? .spokenWord : .music }
    var cachedFileState: AuraCachedFileState { AuraCachedFileState(rawValue: nft.cachedFileState) ?? .notCached }
    var approxLoudnessLUFS: Double? { nft.approxLoudnessLUFS }
}
```

The exact field names can change with the app model. The important part is that the engine receives stable generic media data, not an app persistence object.

## Cache Behavior

`MediaCacheManager` is the boundary between remote-ish media and the local files required by `AVAudioEngine`.

- `localFile(for:)` returns a fully cached local file. If the file is not cached and the network is available, it downloads the file first.
- `localFileWhenPlayable(for:minimumPlayableBytes:)` may return before the full download completes once the partial file can be opened safely and enough bytes are available. A completion task continues writing the rest of the file.
- `prefetch(_:)` starts cache work without blocking playback setup.
- `pin(_:)` and `unpin(_:)` protect or release files from LRU eviction.
- `progress` publishes `CacheProgress` values for UI and app state.
- `loudnessMeasurements` publishes `CachedLoudnessMeasurement` values after cache completion so the app can persist approximate loudness into its own model.

Cache entries are keyed by media ID plus a source fingerprint. If the same media ID points at a new source URL or declared format, the cache treats the old file as stale.

## Play As You Download

Yes, this package can support play-as-you-download in the limited form that fits `AVAudioEngine`: progressive local-file playback.

That means the downloader writes bytes into the final cache file, validates that the partial file can be opened by `AVAudioFile`, returns the local URL once the playable threshold is reached, and keeps filling the tail in the background. The engine still plays a local file. It is not an HLS stream, `AVPlayer` stream, or custom network decoder.

Use `localFileWhenPlayable(for:minimumPlayableBytes:)` for this behavior. Use `localFile(for:)` when the caller needs the complete file before playback.

## Supported Formats

Native `AVAudioFile` formats currently recognized by `AudioTrackSourceFactory`:

- `mp3`
- `m4a`
- `caf`
- `wav`
- `aif`
- `aiff`
- `flac`

Deferred formats:

- `ogg`
- `opus`

Deferred formats require a `DecoderPlugin`. They are intentionally not part of the Phase 6 default path.

## AirPlay-Optimized Route

Use `AirPlayQueuePlayerController` when the host app wants the system playback path Apple recommends for enhanced AirPlay buffering and Spatial Audio. This route is backed by `AVQueuePlayer`, can share `NowPlayingPublisher` and `RemoteCommandPublisher`, and is intended for HomePod, AirPlay speakers, Apple TV, AirPods Spatial Audio, and wireless CarPlay scenarios where route robustness and responsive system controls matter more than the custom AuraPlay graph.

Keep `AudioEngineController` for tracks that need EQ, dynamics, visualizers, custom gapless scheduling, cache recovery, or other `AVAudioEngine` behavior. The package exposes `AuraPlaybackRouteMode` so the host can choose deliberately instead of relying on a hidden automatic switch.

Host apps should also set `AVInitialRouteSharingPolicy` to `LongFormAudio` in Info.plist through Xcode's **AirPlay optimization policy** setting and expose an `AVRoutePickerView` in playback UI. The package demo includes the route picker wrapper and route-mode control; a Swift package executable does not own the shipping app's Info.plist.

## Spatial Audio System Route

`AirPlayQueuePlayerController` exposes `AuraSpatialAudioPolicy` and applies it to each `AVPlayerItem.allowedAudioSpatializationFormats` as queue items are created. Use `.monoAndStereo`, `.multichannel`, `.monoStereoAndMultichannel`, or `.none` to align playback with product and content policy while still leaving the final user experience under system route and Control Center settings.

`AudioSessionManager` can advertise multichannel readiness through `setSupportsMultichannelContent(_:)`, report `currentSpatialAudioEnabled()`, and publish `.spatialAudioEnabledChanged(Bool)` when route or spatial playback capability changes occur. Host UI can use that signal to show availability; it should not force Spatial Audio on.

For future Spatial Audio content, the preferred shape is system playback of HLS variants with multichannel audio alternates, with loudness normalized across stereo and multichannel renditions and appropriate DRC/dialnorm metadata in the content pipeline. AuraPlay's package-level loudness measurement can help app persistence, but final encoding metadata belongs to the host/content pipeline.

The custom `AudioEngineController` path remains non-spatial in Phase 6. `AVSampleBufferAudioRenderer` or a custom spatial renderer would be a later architecture phase.

## AirPods And Now Playing Discipline

AirPods automatic switching depends on clean system intent signals. Treat `NowPlayingPublisher` as a long-form media signal, not a generic status billboard.

Host apps should publish Now Playing only for real user-requested playback. Do not publish placeholder tracks, onboarding sounds, previews, app notifications, chimes, or silent keepalive audio. If the user pauses, pause the engine/player and stop advancing playback state instead of playing silence to keep the route warm. If a future transition absolutely requires silence, keep it below two seconds and document the reason at the call site.

Respect the user's selected route. Use explicit UI or a clear host policy to choose `AuraPlaybackRouteMode.systemAirPlay`; do not automatically steal the route or migrate between the custom engine and `AVQueuePlayer` mid-track until route handoff has a product-approved design.

App-specific chimes and notifications should use Audio Services or another notification-appropriate sound path outside AuraPlay. Press to Mute with `AVAudioApplication` is deferred until a real microphone/call/live-room feature exists. Spatial Audio starts with the `AVQueuePlayer` route before considering a custom `AVAudioEngine` spatial graph.

Phase 6 completion means the package exposes the system route that can participate in platform Spatial Audio where the OS supports it, provides an explicit spatialization policy, advertises multichannel capability through the audio session, documents that custom spatial graph work is deferred, and explicitly rejects Press to Mute implementation in this playback-only package.

## Future Voice Processing Boundary

AuraPlay is a long-form playback package. It does not own microphone capture, voice chat, calls, conferencing, live rooms, recording, mute state, muted talker detection, or voice-processing ducking.

If Auralis later adds a microphone-backed feature, that feature should live in its own module, such as `VoiceChatFeature` or `AuraVoiceEngine`. Prefer `AVAudioEngine` voice processing mode first for Swift app work. Use `AUVoiceProcessingIO` only when the feature truly needs lower-level I/O Audio Unit control.

Future voice features should own Apple voice-processing configuration, including echo cancellation, noise suppression, automatic gain control, mic modes, other-audio ducking, mute APIs, and muted talker detection. If voice chat mixes with AuraPlay playback, the voice feature should configure `AVAudioVoiceProcessingOtherAudioDuckingConfiguration` and product-specific ducking levels; AuraPlay should remain normal media playback.

Muted talker detection must be tied to the platform mute API, not just an app-side Boolean. On macOS-only fallback paths that cannot adopt Apple voice processing, HAL voice activity detection and process mute belong in the future voice feature, with privacy behavior verified on device.

## ASAF/APAC Future Path

Apple Spatial Audio Format (ASAF) and Apple Positional Audio Codec (APAC) are future playback and content-distribution work. The first supported AuraPlay path for future ASAF/APAC assets is the system playback route: `AirPlayQueuePlayerController` backed by `AVQueuePlayer` / `AVPlayer`.

Do not add custom ASAF decode, APAC decode, Higher Order Ambisonics rendering, object-based spatial rendering, or metadata-driven spatial rendering to the Phase 6 `AVAudioEngine` graph. ASAF/APAC assets are not ordinary stereo files, and the custom engine should not strip or fake their spatial semantics.

Authoring and export are also out of scope: no ASAF authoring, APAC encoding, Broadcast Wave export, immersive media export, or production-tool workflows belong in this playback package unless the product explicitly becomes an authoring/mastering tool.

Future host work should validate APAC spatial playback through the system route, stereo compatibility fallback, and HLS/fMP4 delivery once real assets exist.

See `Docs/ADR-004-AirPlay-Optimized-Route.md` and `Docs/ADR-005-AirPods-Now-Playing-Discipline.md` for the tradeoffs, AirPods discipline, ASAF/APAC future path, and deferred custom-renderer path.

## Analysis Output And Visualizers

Analysis output belongs as a playback side-channel. It should not be modeled as audio export.

The current layer exposes `AudioVisualizationFrame` values through `AudioVisualizationPublishing`. `AudioEngineController.startVisualization(configuration:)` installs one tap on the track mixer and publishes per-channel RMS and peak levels through an `AsyncStream` with newest-frame buffering.

Use this for level meters, waveform-style UI, and lightweight beat-reactive visuals. FFT/spectrum output remains future work and should stay optional/rate-limited so visualizers do not compete with playback for CPU.

## Limitations And Non-Goals

Current limitations:

- No direct HLS, APAC, ASAF, or remote streaming path.
- No automatic route switching between the custom engine and `AVQueuePlayer` paths.
- No recording, microphone input, or `AVAudioApplication` Press to Mute pipeline.
- No MIDI or speech synthesis integration.
- No offline render/export, trimming, splitting, concatenation, or mixdown API.
- No spatial, ambisonic, ASAF, or APAC custom graph.
- No DocC catalog, license, changelog, CI workflow, or privacy manifest yet.

Intentional non-goals for the current playback package:

- Do not import app persistence models.
- Do not make SwiftData writes from the engine package.
- Do not add export just to prove effects work; effects should be verified through graph state, analysis, and playback tests unless the product needs saved processed files.

## Implementation Notes

- The graph uses `AVAudioUnitEffect` with Apple's Dynamics Processor Audio Unit because this toolchain does not expose a public `AVAudioUnitDynamicsProcessor` wrapper type.
- Persisted partial files with `Accept-Ranges: bytes` resume through the `ResumableMediaDownloading` path instead of being mistaken for complete cached files.
- SwiftData schema migration for `cachedFileState` and `approxLoudnessLUFS` is app-owned because this package intentionally does not depend on app persistence models.
