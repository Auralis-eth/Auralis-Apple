# Phase 7 Video Engine QA

CI covers unit and mock integration behavior. Physical-device QA is intentionally deferred until real hardware, real media, and system UI flows are available.

## Automated QA Suite

Run from Xcode with the active AuraPlayVideoEngine package scheme, or from the package parent with:

```sh
swift test --package-path AuraPlayVideoEngine
```

The automated suite records coverage for:

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
- Media inspection: audio-track, chapter, high-frame-rate, spatial-video, and video-output helper APIs are available for playback UI and rendering integrations.
- Presentation analysis: preferred transforms are applied before aspect classification; square, portrait, and landscape cases are classified.
- HDR badge gating and metadata fallback: HDR requires content plus display support, and CMFormatDescription color/transfer metadata is inspected when media characteristics are insufficient.
- Poster cache: cached posters are returned without duplicate generation/storage.
- Position persistence: video positions write on cadence, flush on demand, and completion resets position to zero.
- Smooth seeking: rapid scrub requests coalesce and land on the final target.
- Lifecycle safety: periodic time observer add/remove calls are paired, player layers detach when representable views dismantle, teardown is idempotent, and a 100-controller create/destroy stress pass leaves no registered observer tokens behind.
- Subtitle/audio-description empty-state behavior: media without legible or accessibility-audio groups returns empty arrays rather than surfacing an error.
- System integration seams: the video route picker prioritizes video devices, and PiP delegate side effects publish state/restoration without requiring a live system PiP window in CI.
- Integration coordinator: remote skip commands seek the video controller after consuming the latest tick, media-session pause/resume events pause/play and flush position, gateway stalls re-resolve and resume at the last tick, end-of-item marks playback complete, and video ticks publish through the Now Playing adapter protocol.

## Explicitly Out Of Scope For Playback

The Phase 7 engine is playback-only. It does not implement editing/composition timelines, Core Image/Metal/Vision processing pipelines, or export sessions. Those areas should be tracked as separate future packages or feature phases rather than treated as unfinished playback work.

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
