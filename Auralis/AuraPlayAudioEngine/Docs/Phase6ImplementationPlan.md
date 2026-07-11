# Phase 6 Implementation Plan

AuraPlayAudioEngine will ship as a generic audio package. App models such as `NFT` adapt into `AuraPlayableMedia`; the engine never imports SwiftData, NFT models, wallet models, or app routing code.

## Package Boundary

- `AuraPlayableMedia` is the generic media contract.
- `AnyAuraPlayableMedia` is the type-erased handoff type for queues and app adapters.
- Cache and loudness state are modeled as values in this package, but app persistence owns writing them to SwiftData.
- AVFoundation graph code stays inside this package; app UI and Phase 8 queue state call through protocols.

## Ticket Landing Order

1. P6-001: implement live `AudioSessionManager` in one file that owns access to the shared system audio session.
2. P6-002: implement `MediaCacheManager` as an actor with URL resolution hooks, disk index, LRU eviction, progress streams, and schema-adapter callbacks.
3. P6-003: implement `AudioEngineController` with the fixed graph: primary player + prebuffer player -> track mixer -> EQ -> dynamics -> main mixer.
4. P6-008: finish `AudioTrackSourceFactory` with AVAudioFile validation and corrupted-file mapping before deep scheduling work.
5. P6-004: implement `GaplessScheduler` on the audio-engine serial queue with cached-only true gapless and brief-gap fallback.
6. P6-005: add recovery coordinator for configuration changes, interruptions, underruns, position preservation, and watchdog retry.
7. P6-006: wire EQ, dynamics, and RMS approximate loudness measurement from completed cache files.
8. P6-007: layer `AutoMixController` on top of the scheduler without duplicating scheduling.
9. P6-009: add Now Playing and remote command publishers as shared audio/video infrastructure.
10. P6-011: add the opt-in `AVQueuePlayer` route for AirPlay-optimized playback, document host Info.plist requirements, and surface an AirPlay route picker in the demo.
11. P6-012: implement and document system-route Spatial Audio policy: apply `AuraSpatialAudioPolicy` to `AVPlayerItem`, advertise multichannel capability from `AudioSessionManager`, publish spatial capability changes, keep custom engine spatial rendering deferred, and document AirPods Now Playing discipline plus Press to Mute scope.
12. P6-013: document ASAF/APAC as a future system-route playback path: first support through `AVQueuePlayer`/`AVPlayer`, no custom ASAF/APAC decode or render in Phase 6, no authoring/export pipeline, and QA stereo fallback once real assets exist.
13. P6-014: document future voice processing boundary: no voice processing, ducking, muted talker detection, HAL voice activity detection, microphone input, or Press to Mute in AuraPlay playback; future microphone/call/live-room modules own `AVAudioEngine` voice processing, `AUVoiceProcessingIO` only when required, platform mute APIs, and voice QA.
14. P6-010: expand tests into unit, offline-render integration, and physical-device QA sign-off.

## Generic Adapter Shape

The app-side NFT adapter should be a tiny value type, not a package dependency:

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

If the real NFT model uses different field names, keep the mapping there. Do not bend engine protocols around app storage details.

## Implementation Notes

- Use actors for cache index and download coordination.
- Use a dedicated serial queue or custom executor boundary for AVAudioEngine graph mutations.
- Keep `@MainActor` out of core engine types unless a type truly touches UI or MediaPlayer main-thread APIs.
- Keep URLSession and gateway fallback behind protocols so cache tests can run offline.
- Do not add Ogg, Opus, HLS, ASAF/APAC decode, ASAF/APAC authoring/export, ambisonic decode, Spatial Audio graph work, voice processing, other-audio ducking, muted talker detection, HAL voice activity detection, Press to Mute, microphone input, or true BS.1770 LUFS in Phase 6 v1.

## Definition Of Prepared

- Library target exists and is importable.
- Public generic contracts compile.
- Phase 6 plan, ADR-003, and manual QA checklist exist.
- Pure contract tests exist and can grow into the Layer 1 suite.

## Current Release Gate

Automated package validation covers the cache actor, resumable partial downloads, progressive readiness, bounded read-ahead scheduling, native MP3/FLAC fixture decoding, generated AAC/ALAC decoding, format dispatch, live graph topology, gapless render-frame boundary planning, EQ/dynamics math, cache-completion loudness measurement handoff, render-frame-driven crossfade progress, underrun pause/reschedule/recovery, command-target cleanup by construction, remote-command skip interval configuration, Now Playing snapshots, AirPlay-optimized queue contract, spatial audio policy application, and multichannel/spatial session intent. Hardware callback timing, audible gaplessness, and real AirPlay/spatial route behavior remain device QA items.

For the release decision requested here, SwiftData migration, host playback-flow wiring, host Info.plist AirPlay policy, Now Playing discipline, and physical-device QA are explicit host-app gates. Package-side Phase 6 infrastructure is ready once the host app wires the package into real playback flows, wires the generic media adapter, persists emitted loudness measurements, sets `AVInitialRouteSharingPolicy` to `LongFormAudio`, publishes Now Playing only for real long-form media, keeps chimes/previews/placeholders outside AuraPlay, avoids silent keepalive playback after pause, and signs off `Docs/QA/Phase6DeviceManualChecklist.md` on device.

Spatial Audio is complete for Phase 6 as implemented system-route policy through `AVQueuePlayer`/`AVPlayerItem`, plus audio-session multichannel advertising and spatial capability events. ASAF/APAC is complete for Phase 6 as a documented future system-route playback path with no custom decode/render or authoring/export pipeline. Voice processing, other-audio ducking, muted talker detection, HAL voice activity detection, and Press to Mute are complete for Phase 6 as explicit non-goals until a real microphone/call/live-room feature exists.
