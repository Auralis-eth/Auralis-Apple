# Phase 7 Video Engine QA

CI covers unit and mock integration behavior. Physical-device QA is intentionally deferred until real hardware, real media, and system UI flows are available.

## Automated QA Suite

Run from Xcode with the active AuraPlayVideoEngine package scheme, or from the package parent with:

```sh
swift test --package-path AuraPlayVideoEngine
```

The automated suite records coverage for:

- Package platform support: the package declares iOS 26, macOS 26, and visionOS 26 support so immersive playback policy APIs can be consumed by visionOS hosts.
- URL validation: unresolved `ipfs://` playback URLs and WebM are rejected; resolved HTTPS MP4/MOV/HLS-style URLs are accepted.
- Media adapter contract: host media objects can conform to `VideoPlayableMedia` and load through `VideoPlayerController`.
- Asset loading: `VideoAssetLoader` creates `AVURLAsset` through one factory path, supports explicit async preloading plans, applies buffering policy to generated player items, and can route manifest-available media to local files.
- Progressive caching: eligible HTTPS progressive media can be rewritten to the custom cache scheme, sparse byte ranges merge on disk, and completed cache files become local playback candidates.
- Offline downloads: progressive file and HLS download managers publish manifest-backed state for queued/downloading/available/failed/cancelled assets.
- Buffering policy: gateway hosts use a 10-second forward buffer; direct HTTPS uses automatic buffering.
- Stall fallback policy: gateway stalls trigger one fallback decision after the named threshold; direct HTTPS stalls do not.
- Playback observation: progress ticks are registered at a 60fps interval, and waiting-reason changes are exposed as playback events.
- Playback speed: all six speed labels are stable, pitch algorithms avoid varispeed, and selected speed persists under `com.auraplay.videoPlaybackSpeed`.
- Queue playback: `VideoPlaybackQueueController` loads the next host media item when completion is observed.
- Media inspection: audio-track, chapter, high-frame-rate, immersive profile, and video-output helper APIs are available for playback UI and rendering integrations.
- Immersive playback policy: 2D, stereo, spatial video, Apple Projected Media Profile, and Apple Immersive Video assets map to honest custom-layer, AVKit, Quick Look, or RealityKit presentation routes instead of treating every player surface as equivalent.
- AVKit immersive handoff: host apps can receive a URL, metadata, capabilities, and requested expanded/immersive experience without this package owning `AVPlayerViewController`.
- Presentation analysis: preferred transforms are applied before aspect classification; square, portrait, and landscape cases are classified.
- HDR badge gating and metadata fallback: HDR requires content plus display support, and CMFormatDescription color/transfer metadata is inspected when media characteristics are insufficient.
- Poster cache: cached posters are returned without duplicate generation/storage.
- Position persistence: video positions write on cadence, flush on demand, and completion resets position to zero.
- Smooth seeking: rapid scrub requests coalesce and land on the final target.
- Lifecycle safety: periodic time observer add/remove calls are paired, player layers detach when representable views dismantle, teardown is idempotent, and a 100-controller create/destroy stress pass leaves no registered observer tokens behind.
- Subtitle/audio-description empty-state behavior: media without legible or accessibility-audio groups returns empty arrays rather than surfacing an error.
- System integration seams: the video route picker prioritizes video devices, and PiP delegate side effects publish state/restoration without requiring a live system PiP window in CI.
- Integration coordinator: remote skip commands seek the video controller after consuming the latest tick, media-session pause/resume events pause/play and flush position, gateway stalls re-resolve and resume at the last tick, end-of-item marks playback complete, and video ticks publish through the Now Playing adapter protocol.
- Multiview coordinator: synchronized mode connects participants to one playback coordination medium, independent mode leaves players uncoordinated, preferred route roles update the routing arbiter, network priority changes are applied per participant, duplicate IDs are rejected, and coordination failures leave participant state unchanged.

## Explicitly Out Of Scope For Playback

The Phase 7 engine is playback-only. It does not implement editing/composition timelines, Core Image/Metal/Vision processing pipelines, export sessions, live Apple Immersive Video production workflows, or host-owned visionOS theater environments.

A future production-tools package would need its own QA contract for SMPTE 2110-22/30/41 transport, direct ProRes frame preservation, ASAF PCM audio layout, per-frame JSON parsing, Immersive Media Support metadata authoring, MEBX metadata tracks, and MOV files marked with `kVTProjectionKind_AppleImmersiveVideo`/`vexu` metadata. Those are not regressions against this playback engine.

A visionOS host app needs its own QA contract for AVKit fullscreen docking, custom `ImmersiveSpace` scenes, Reality Composer Pro docking-region placement, media reflections, environment probes, passthrough tint/brightness, reverb presets, immersive environment picker discovery, and SharePlay environment-state synchronization through `AVPlayerViewController.groupExperienceCoordinator`.

## Physical Device QA Checklist

These items remain manual because CI cannot honestly validate AVPlayer rendering, hardware routes, system PiP windows, HDR output, or phone-call interruption behavior.

- [ ] MP4/H.264 and MP4/HEVC play with audio and video in sync.
- [ ] HLS adapts bitrate under Network Link Conditioner throttling.
- [ ] Dolby Vision or HDR10 visibly renders with expanded range on an HDR device.
- [ ] Landscape video rotates the player; square/portrait does not offer rotation.
- [ ] Poster frames appear for video items lacking metadata artwork.
- [ ] Subtitle toggle works; Audio Description toggle present for AD content.
- [ ] Swiping away auto-enters PiP; tapping the PiP window restores at the correct position.
- [ ] PiP drag/resize behaves per standard system UX.
- [ ] AirPlay mirrors to Apple TV; local screen shows controls, not a forced mirror.
- [ ] Each speed option is natural-pitched at 1.5x and 2x.
- [ ] Scrubbing is smooth, including to unbuffered positions.
- [ ] Gateway stall triggers fallback and recovers without user action.
- [ ] Progressive MP4 starts playback through `ProgressiveVideoCachingPipeline`, services byte-range requests, streams network bytes incrementally into AVFoundation and disk, cancels in-flight range fetches when AVFoundation cancels loading requests, and reuses the completed local cache file on the next load.
- [ ] HLS offline download creates a playable local package and reuses the manifest entry offline.
- [ ] Progressive MP4 background download survives app suspension and resumes through the manifest entry.
- [ ] Phone call pauses video and resumes at the same position.
- [ ] Closing and reopening a partially-watched video offers resume from the saved position.
- [ ] A finished video advances to the next queue item.
- [ ] Lock Screen Now Playing shows correct metadata with the video media type.
- [ ] Known stereo, spatial MV-HEVC, APMP, and Apple Immersive Video local assets map to the expected `VideoImmersiveMediaProfile` values through the playback assistant or track-characteristics fallback.
- [ ] Inline custom-layer playback does not claim spatial, APMP, or Apple Immersive presentation; immersive content is labeled or routed according to `VideoImmersivePlaybackPolicy`.
- [ ] On visionOS, full spatial/APMP/Apple Immersive presentation is opened through a host-owned Quick Look, AVKit, or RealityKit path rather than `PlayerContainerView`.
- [ ] AVKit `AVExperienceController` expanded presentation can disable automatic transition to immersive when portal treatment is desired.
- [ ] AVKit `AVExperienceController` immersive transition reports available experiences and transition context changes through the host adapter.
- [ ] AVKit fullscreen playback docks comfortably in a host-owned custom environment, with a clear sightline and no distracting objects between the viewer and media.
- [ ] Custom environment docking-region scale and placement are checked on Apple Vision Pro, not only in Reality Composer Pro.
- [ ] Media reflections, environment probes, passthrough tint/brightness, and reverb presets support the viewing experience without pulling attention away from the video.
- [ ] Immersive environment picker entries show correct title/thumbnail metadata and open the expected host immersive space.
- [ ] SharePlay-enabled viewing syncs both media playback and environment state through the host AVKit/GroupActivities adapter.
- [ ] RealityKit APMP and Apple Immersive Video playback uses progressive immersive viewing mode with a matching progressive `ImmersionStyle`.
- [ ] RealityKit spatial video playback uses portal or full immersive viewing mode with mixed immersion and coexist behavior where appropriate.
- [ ] Spatial/3D/immersive playback keeps custom overlays minimal so controls do not fight the content depth.
