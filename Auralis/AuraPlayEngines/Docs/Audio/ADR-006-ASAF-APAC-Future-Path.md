# ADR-006: ASAF/APAC Future Path

## Status

Accepted as future playback and content-distribution guidance. Not part of Phase 6 runtime implementation.

## Context

Apple Spatial Audio Format (ASAF) and Apple Positional Audio Codec (APAC) are designed for high-resolution immersive audio delivery. ASAF can combine Higher Order Ambisonics, objects, and time-varying metadata. APAC efficiently transports that content for playback and streaming.

This is not the same problem as AuraPlay's Phase 6 custom audio graph. The current `AudioEngineController` route is optimized for cached local files, EQ, dynamics, visualization, loudness normalization, gapless scheduling, and recovery. It is not an ASAF renderer and should not pretend that ASAF/APAC assets are ordinary stereo files.

## Decision

The first supported AuraPlay path for future ASAF/APAC playback is the system playback route: `AirPlayQueuePlayerController` backed by `AVQueuePlayer` / `AVPlayer`.

AuraPlay will not add custom ASAF decode, APAC decode, object rendering, Higher Order Ambisonics rendering, or metadata-driven spatial rendering to the Phase 6 `AVAudioEngine` graph.

AuraPlay will not add ASAF authoring, APAC encoding, Broadcast Wave export, immersive media export, or production-tool workflows to this package unless the product explicitly becomes an authoring or mastering tool.

## Consequences

- ASAF/APAC support starts as a system-route playback feature, not a custom-engine feature.
- APAC/HLS delivery should be evaluated through `AVPlayer` capabilities and Apple platform support before adding package-specific streaming code.
- Stereo compatibility tracks should be expected for assets that include APAC spatial audio, and the host app should choose the best supported route per platform/device.
- The current custom engine remains responsible for non-spatial cached playback, effects, visualization, gapless scheduling, and recovery.
- Any custom spatial graph work becomes a later architecture phase with product requirements, real assets, device QA, and performance validation.

## Phase 6 Scope

Phase 6 is complete when the package documents the ASAF/APAC boundary and points future work at the `AVQueuePlayer` system route. Phase 6 does not include:

- custom ASAF parsing
- APAC decode or encode
- ASAF metadata rendering
- Higher Order Ambisonics rendering
- object-based spatial rendering
- HLS APAC streaming implementation
- ASAF/APAC authoring or export

## Future QA Requirements

When real ASAF/APAC assets exist, add device QA for:

1. APAC spatial asset playback through the system route on supported iOS/macOS/visionOS hardware.
2. Stereo compatibility fallback when APAC spatial playback is unavailable or disabled.
3. Route behavior with AirPods and compatible spatial audio output devices.
4. HLS/fMP4 APAC delivery if the host app streams immersive assets.
5. Now Playing and remote command behavior for ASAF/APAC assets.
6. Battery and thermal behavior with long-form APAC spatial playback.

## References

- Apple Spatial Audio Format (ASAF)
- Apple Positional Audio Codec (APAC)
- `AirPlayQueuePlayerController`
- ADR-004 AirPlay-Optimized Playback Route
- ADR-005 AirPods Behavior And Now Playing Discipline
