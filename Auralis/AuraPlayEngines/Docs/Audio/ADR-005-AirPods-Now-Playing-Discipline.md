# ADR-005: AirPods Behavior And Now Playing Discipline

## Status

Accepted for playback package policy and host-app guidance.

## Phase 6 Completion Definition

Spatial Audio is complete for Phase 6 by exposing the `AVQueuePlayer` system route, applying an explicit `AuraSpatialAudioPolicy` to `AVPlayerItem.allowedAudioSpatializationFormats`, advertising multichannel content capability through `AudioSessionManager`, and explicitly deferring custom `AVAudioEngine` spatial or ambisonic graph work to a future product phase.

Press to Mute is complete for Phase 6 by documenting it as out of scope for the playback package. No `AVAudioApplication` mute API is adopted until Auralis has a real microphone-backed feature such as calls, live rooms, recording, or conferencing.

The host app still must complete three shipping integration gates:

1. Wire the package into real playback flows.
2. Set Info.plist `AVInitialRouteSharingPolicy` to `LongFormAudio`.
3. Enforce Now Playing discipline: only real long-form media, no chimes, previews, placeholders, or silent keepalives.

## Context

AirPods automatic switching uses user intent signals such as Now Playing registration and input audio activity. AuraPlay is a long-form media playback package, so correct Now Playing metadata is part of the system contract, not just Lock Screen decoration.

The same WWDC guidance draws boundaries that matter for this package:

- media apps should register Now Playing for real long-form playback
- apps should avoid playing silence after a user pauses audio
- media apps should respect the user's selected route
- app-specific chimes and notifications should use notification/chime APIs instead of the media playback pipeline
- Press to Mute is for call or microphone sessions, not playback-only engines
- Spatial Audio support is strongest through system playback APIs such as `AVPlayer`/`AVQueuePlayer`, with custom rendering as a separate architecture path
- `AVPlayerItem.allowedAudioSpatializationFormats` lets the system route choose whether mono/stereo, multichannel, both, or neither are eligible for spatialization
- `AVAudioSession.setSupportsMultichannelContent(_:)`, route changes, and spatial playback capability notifications help host UI represent Spatial Audio availability without forcing it

## Decision

AuraPlay treats Now Playing as a long-form playback signal. The host app should publish Now Playing only for real user-requested media playback, such as a track, episode, album item, or playlist item.

AuraPlay must not publish placeholder, preview, notification, chime, onboarding, or silent keepalive audio through Now Playing. These sounds are not tracks and should not influence AirPods automatic switching.

AuraPlay must not keep an audio route alive by playing silence after pause. If a future transition requires silence as a technical bridge, that silence should be bounded to less than two seconds and documented at the call site.

AuraPlay respects the user's selected route. `AirPlayQueuePlayerController` remains an explicit host-selected route for AirPlay/HomePod/Apple TV/wireless CarPlay optimization. The package should not silently migrate between the custom engine route and the system route unless a future route-handoff design preserves queue identity, position, user intent, and product semantics.

## Voice Processing And Press To Mute Boundary

AuraPlay does not adopt voice processing, `AVAudioApplication` input mute APIs, muted talker detection, or other-audio ducking in the playback package because it has no microphone, call, conferencing, live room, or recording pipeline.

If Auralis later adds microphone-backed features, voice processing and mute support should live in that feature boundary and should be designed around the platform-specific contract:

- Prefer `AVAudioEngine` voice processing mode first for Swift app work.
- Use `AUVoiceProcessingIO` only when the feature truly needs lower-level I/O Audio Unit control.
- iOS CallKit apps get Press to Mute support through CallKit behavior.
- Non-CallKit communication features can observe `AVAudioApplication` mute-state notifications and keep app mute state synchronized.
- macOS communication features must also apply input muting to uplink audio when the mute gesture occurs.
- Other-audio ducking belongs to the voice feature when voice chat and media playback overlap.
- Muted talker detection must use the platform voice-processing mute API, not just an app-side Boolean.
- macOS-only fallback paths that cannot adopt Apple voice processing may use HAL voice activity detection and process mute, but that belongs in the future voice feature.

That work should not be smuggled into the long-form playback engine.

## Spatial Audio Boundary

Spatial Audio starts with the system route because `AVPlayer`/`AVQueuePlayer` are system-supported playback paths and already align with the AirPlay-optimized route.

`AirPlayQueuePlayerController` owns package-level spatialization policy for system playback. It applies `AuraSpatialAudioPolicy` to each `AVPlayerItem`, allowing the host to permit mono/stereo, multichannel, both, or no spatialization. System settings, route capabilities, and user preferences still determine the final rendered experience.

`AudioSessionManager` owns package-level multichannel signaling and spatial availability observation. It can call `setSupportsMultichannelContent(_:)`, report current spatial enablement, and publish `.spatialAudioEnabledChanged(Bool)` for route or capability changes.

Future multichannel HLS support should use the system route, normalize loudness across stereo and multichannel renditions, and rely on the content pipeline for DRC and dialnorm metadata.

A custom Spatial Audio or ambisonic graph inside `AVAudioEngine` is a separate architecture phase. It should not be added to the default Phase 6 graph without product requirements, device QA, and performance validation.

## ASAF/APAC Future Path

Apple Spatial Audio Format (ASAF) and Apple Positional Audio Codec (APAC) are future playback and content-distribution work, not Phase 6 runtime implementation.

The first supported AuraPlay path for future ASAF/APAC playback is the system playback route: `AirPlayQueuePlayerController` backed by `AVQueuePlayer` / `AVPlayer`. ASAF can combine Higher Order Ambisonics, objects, and time-varying metadata, so it should not be treated as an ordinary stereo file inside the Phase 6 `AVAudioEngine` graph.

AuraPlay will not add custom ASAF decode, APAC decode, object rendering, Higher Order Ambisonics rendering, or metadata-driven spatial rendering to the Phase 6 custom engine.

AuraPlay will not add ASAF authoring, APAC encoding, Broadcast Wave export, immersive media export, or production-tool workflows unless the product explicitly becomes an authoring or mastering tool.

Future ASAF/APAC support should expect stereo compatibility fallback where assets provide it, and should validate APAC/HLS delivery through system playback before adding package-specific streaming code.

## Host App Requirements

The host app should:

1. Wire `AuraPlayAudioEngine` into real playback flows, including app queue state, user controls, route selection, cache persistence, and app-owned `AuraPlayableMedia` adapters.
2. Set Info.plist `AVInitialRouteSharingPolicy` to `LongFormAudio` through Xcode's **AirPlay optimization policy** setting.
3. Publish Now Playing metadata when real long-form playback begins or resumes.
4. Clear or pause Now Playing state when playback ends or the user pauses.
5. Avoid publishing Now Playing for short app sounds, previews, notifications, chimes, placeholders, onboarding sounds, or silent keepalives.
6. Use Audio Services or another notification-appropriate sound path for app-specific chimes.
7. Respect the user's current audio route and use explicit UI or clear host policy for route changes.
8. Validate AirPods automatic switching behavior on device because CI cannot emulate user-owned AirPods moving between Apple devices.

## Consequences

- AirPods automatic switching gets clean long-form playback signals.
- The package avoids accidental route stealing from placeholder or silent audio.
- Voice processing, other-audio ducking, muted talker detection, and Press to Mute remain available for a future microphone feature without polluting the playback package.
- Spatial Audio has an implemented system-route policy and session capability signal before any custom graph work.
- ASAF/APAC playback starts with `AVQueuePlayer`/system playback, not custom decode/render in the Phase 6 engine.
- ASAF/APAC authoring and export remain out of scope for this playback package.
