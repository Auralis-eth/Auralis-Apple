# ADR-004: AirPlay-Optimized Playback Route

## Status

Accepted for the first AirPlay optimization pass.

## Context

AuraPlay's Phase 6 playback route is built on `AVAudioEngine`, `AVAudioPlayerNode`, progressive local-file caching, bounded read-ahead scheduling, EQ, dynamics, loudness normalization, visualization taps, and gapless handoff logic.

That route is still the right tool when the product needs the custom graph. It is the mixing desk: every signal passes through AuraPlay's own processing chain before it reaches the speakers.

WWDC guidance for enhanced AirPlay audio buffering points at a different tool family: `AVPlayer` / `AVQueuePlayer`, or a custom `AVSampleBufferAudioRenderer` plus `AVSampleBufferRenderSynchronizer` stack. `AVQueuePlayer` is the simplest path and automatically participates in the system's enhanced AirPlay buffering behavior when routed to AirPlay-compatible devices.

## Decision

AuraPlay now has two playback routes:

- **Custom engine route**: `AudioEngineController` + `GaplessScheduler` for cached local files, effects, visualization, gapless scheduling, and recovery logic.
- **System AirPlay route**: `AirPlayQueuePlayerController` backed by `AVQueuePlayer` for AirPlay/HomePod/Apple TV/wireless CarPlay scenarios where system-perfect route behavior matters more than the custom graph.

The system route is opt-in. The host app chooses it deliberately through `AuraPlaybackRouteMode.systemAirPlay`; the package does not silently switch routes mid-track.

## Consequences

- AirPlay-optimized playback gets the system buffering path that Apple recommends for most apps.
- The custom `AVAudioEngine` route remains intact for EQ, dynamics, visualization, gapless cache scheduling, and offline-focused behavior.
- The system route should prefer already cached local URLs from `MediaCacheManager` when the app wants offline/cache consistency.
- Remote command and Now Playing integration can be shared through the existing `RemoteCommandPublisher` and `NowPlayingPublisher` contracts.
- Route handoff is a host-app responsibility for now. The first implementation avoids automatic mid-track migration because preserving position, queue identity, effect state, and user expectations needs product-level rules.

## Host App Requirements

For long-form audio and intelligent AirPlay suggestions, the host app should:

1. Configure `AVAudioSession` with category `.playback`, the correct mode, route sharing policy `.longFormAudio`, and AirPlay-capable options.
2. Set the Info.plist `AVInitialRouteSharingPolicy` key to `LongFormAudio` using Xcode's **AirPlay optimization policy** setting.
3. Expose an `AVRoutePickerView` in the playback UI so people can choose HomePod, AirPlay speakers, Apple TV, or CarPlay routes.
4. Keep Now Playing metadata and remote commands wired while either route is active.

## AirPods And Now Playing Discipline

AirPods automatic switching uses user intent signals such as Now Playing registration and input audio activity. AuraPlay is a long-form media playback package, so correct Now Playing metadata is part of the system contract, not just Lock Screen decoration.

AuraPlay treats Now Playing as a real long-form playback signal. The host app should publish Now Playing only for user-requested media playback, such as a track, episode, album item, or playlist item. It must not publish placeholder, preview, notification, chime, onboarding, or silent keepalive audio through Now Playing.

AuraPlay must not keep an audio route alive by playing silence after pause. If a future transition requires silence as a technical bridge, that silence should be bounded to less than two seconds and documented at the call site.

AuraPlay respects the user's selected route. `AirPlayQueuePlayerController` remains an explicit host-selected route for AirPlay/HomePod/Apple TV/wireless CarPlay optimization. The package should not silently migrate between the custom engine route and the system route unless a future route-handoff design preserves queue identity, position, user intent, and product semantics.

App-specific chimes and notifications should not use AuraPlay's long-form media pipeline and should not publish Now Playing. The host app should use Audio Services or another notification-appropriate sound path for those sounds so they do not influence AirPods automatic switching.

## Press To Mute Boundary

AuraPlay does not adopt `AVAudioApplication` input mute APIs in the playback package because it has no microphone, call, conferencing, live room, or recording pipeline.

If Auralis later adds microphone-backed features, mute support should live in that feature boundary and should be designed around the platform-specific contract:

- iOS CallKit apps get Press to Mute support through CallKit behavior.
- Non-CallKit communication features can observe `AVAudioApplication` mute-state notifications and keep app mute state synchronized.
- macOS communication features must also apply input muting to uplink audio when the mute gesture occurs.

That work should not be smuggled into the long-form playback engine.

## Spatial Audio Boundary

Spatial Audio is future work. The first exploration should start with the system route because `AVPlayer`/`AVQueuePlayer` are system-supported playback paths and already align with the AirPlay-optimized route.

A custom Spatial Audio or ambisonic graph inside `AVAudioEngine` is a separate architecture phase. It should not be added to the default Phase 6 graph without product requirements, device QA, and performance validation.

## Deferred Work

`AVSampleBufferAudioRenderer` plus `AVSampleBufferRenderSynchronizer` remains the future option if AuraPlay needs enhanced AirPlay buffering and a custom rendering pipeline at the same time. That should be treated as a separate architecture phase, not a small extension of the current `AVAudioEngine` graph.
