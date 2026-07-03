# AuraPlayVideoEngine Journal

## The Big Picture

AuraPlayVideoEngine is the video booth beside AuraPlay's music stage. The main app can keep handling wallets, NFTs, queue arbitration, receipts, and gateway policy; this package focuses on getting moving pictures onto the screen without turning the rest of the app into a media plumbing maze.

The first real version now has a player, a screen, a pulse, and a set of plugs for the host app. It still expects the app to hand it a resolved HTTPS URL, but once it gets one, it can build an `AVPlayerItem`, expose a custom `AVPlayerLayer`, publish playback events, and tear everything down cleanly.

## Architecture Deep Dive

Think of the package like a theater:

- `VideoPlayerController` is the projectionist. It loads the reel, watches the projector, reports stalls, and shuts the booth down in the right order.
- `PlayerContainerView` is the screen. On iOS it is a `UIView` whose backing layer is `AVPlayerLayer`; on macOS it is an `NSView` hosting the same kind of layer.
- `ObserverBag` is the clipboard at the booth door. Every KVO and notification observer goes on it so nothing gets forgotten at closing time.
- `ChaseTimeSeekCoordinator` is the usher during a rush. When twenty scrub requests arrive at once, it does not try to seat every request individually; it keeps moving toward the newest seat.
- `VideoPlayableMedia` is the visitor badge. NFT models, queue rows, or library objects can wear it for the engine without becoming engine-owned types.
- The adapter protocols are the loading dock. The app can bring its real gateway resolver, Now Playing publisher, remote-command stream, session manager, artwork cache, and playback-state store without this package importing those app modules.

## The Codebase Map

- `Sources/AuraPlayVideoEngine/VideoPlayerController.swift`
  Core AVPlayer pipeline, state publishing, KVO, periodic time ticks, end/stall notifications, and teardown.
- `Sources/AuraPlayVideoEngine/PlayerContainerView.swift`
  The custom layer-backed player surface for iOS and macOS.
- `Sources/AuraPlayVideoEngine/VideoPresentationAnalyzer.swift`
  Aspect/orientation analysis, HDR detection gate, and poster-frame generation.
- `Sources/AuraPlayVideoEngine/IntegrationProtocols.swift`
  Host-app boundary for gateway fallback, persistence, Now Playing, remote commands, media session, and artwork.
- `Sources/AuraPlayVideoEngine/*Coordinator.swift`
  Small testable helpers for seeking, stalls, and position persistence.
- `Examples/AuraPlayVideoEngineDemo/`
  A minimal SwiftUI harness for manual loading and playback.
- `docs/decisions/`
  ADR-004 and ADR-005 explain why the package streams resolved HTTPS directly and uses one custom AVPlayerLayer surface.

## Tech Stack & Why

Swift Package Manager keeps the engine isolated and testable before it is wired into the app shell.

AVFoundation is the right tool for MP4/MOV/HLS playback because `AVPlayer` already knows how to stream, buffer, seek, observe status, and hand frames to `AVPlayerLayer`.

SwiftUI is used for the demo and the representable bridge, but SwiftUI `VideoPlayer` is intentionally skipped. It is convenient for simple playback, but AuraPlay needs the raw layer for PiP, custom controls, gestures, overlays, and future polish.

Swift Testing covers the policy and coordination logic. That keeps the quick checks honest without pretending CI can prove real HDR rendering, AirPlay hardware discovery, or system PiP window behavior.

## The Journey

### 2026-07-01 — The Video Room Has A Name Before It Has Gear

This package started as a reserved room for future AuraPlay video work. No playback code lived here yet, and no existing app media code moved.

That restraint mattered. Video brings player lifetime, captions, artwork, routing, background behavior, and NFT media metadata. The package gave that future design a clean address without smuggling in a half-designed engine too early.

### 2026-07-03 — The Projector Gets A Teardown Checklist

The first implementation landed the Phase 7 skeleton: library target, custom player surface, controller, lifecycle observers, seeking helpers, presentation helpers, persistence cadence, demo harness, ADRs, QA checklist, and tests.

The big bug avoided here is the classic AVPlayer observer trap: adding a periodic time observer and then letting the player die without removing it. That crash is the media-engine equivalent of leaving a ladder across the stage in the dark. `VideoPlayerController.teardown()` now removes the time observer before releasing the item, invalidates KVO and notification tokens, and is safe to call twice.

The second important lesson is that smooth scrubbing is not "call seek a lot." Dragging a scrubber can fire a storm of targets. The chase-time coordinator keeps only the latest destination while a seek is in flight, so the player lands where the user actually ended up.

### 2026-07-03 — The Media Object Learns To Wear A Badge

The engine originally knew how to load a URL and describe Now Playing metadata, but it did not have one clean shape for "a thing that can be played as video." That would force app code to unpack NFT models or queue rows into loose parameters every time.

`VideoPlayableMedia` fixes that. It is deliberately small: identity, title, optional artist, optional artwork, and the already-resolved playback URL. The app can make an NFT, library row, or queue item conform without the engine importing those models. It is a passport stamp, not a new citizenship.

### 2026-07-03 — The Loading Dock Gets A Foreman

The first pass had excellent plugs: gateway resolver, Now Playing publisher, remote-command stream, media-session manager, artwork cache, and playback-state store. But plugs sitting on a shelf do not move boxes. Phase 7 needed one owner to connect them to the running player.

`VideoPlaybackIntegrationCoordinator` is that foreman. It listens to controller ticks and writes position, pushes video metadata to Now Playing, turns remote skip commands into smooth seeks, pauses on session events, marks completion, and waits out gateway stalls before asking for the next resolved URL. The host app still brings the real adapters, but the engine now owns the choreography.

A few smaller lessons came with it. Preferences belong at the edge of helpers, not scattered through controls, so subtitle language and speed now persist behind the manager/controller APIs. HDR detection also learned not to trust a single label: when AVFoundation does not mark a track with `.containsHDRVideo`, the detector checks format-description color primaries and transfer functions like a bouncer checking a second ID.

### 2026-07-03 — The Ticket Booth Learns To Count Its Stubs

The automated gate exposed two subtle async test races. The coordinator listens to player ticks, remote commands, and media-session events on separate streams. The tests were firing a tick and immediately asking a remote command to use it, which is like shouting a new timecode at the projectionist and then grading the next command before the message reaches the booth. The fix was not to sleep and hope; the tests now wait for an observable adapter effect before depending on tick-derived state.

We also gave the periodic time observer its own tiny registrar seam. AVPlayer is still the real runtime player, but tests can now count every observer ticket handed out and every ticket taken back. That made the idempotent teardown test and 100-controller stress test precise instead of ceremonial.

### 2026-07-03 — The Projectionist Remembers The Speed Dial

Two small-looking bugs were actually user-experience potholes. First, the speed helper could remember 1.5x, but the player controller resumed with a plain `play()`, like a projectionist carefully labeling the speed dial and then ignoring it when the lights went down. `VideoPlayerController` now reads the stored speed when loading and playing, applies the matching pitch algorithm to the current item, and resumes by setting the player rate to the selected speed.

Second, gateway fallback learned the difference between "buffering" and "stuck." A player can still report buffering while time is creeping forward, so retrying the next gateway just because the state stayed `.buffering` was too eager. The coordinator now compares the latest tick after the stall threshold; if playback moved, it stays on the current gateway instead of yanking the reel mid-scene.

The regression tests cover both lessons: stored speed survives pause/play through the controller, and a stall with an advanced tick does not ask the gateway resolver for a replacement URL.

### 2026-07-03 — The Booth Gets Better Instruments, Not A Film Studio

The checklist audit found a real distinction hiding in plain sight: some missing pieces belonged to playback, and some belonged to a future editing suite. We filled in the playback instruments.

`VideoAssetLoader` is now the ticket scanner for assets. Instead of every caller building `AVURLAsset` by hand, assets go through one path that can preload tracks, duration, common metadata, media-selection characteristics, and playability when the host wants that guarantee. The player controller uses that path too, but keeps preloading opt-in so tests and placeholder URLs do not accidentally turn into network probes.

The player pulse also got sharper. Progress ticks now register at a 60fps interval for smooth custom controls, and the controller publishes `reasonForWaitingToPlay`, which is the difference between saying "the projector stopped" and knowing whether it is buffering, minimizing stalls, or missing an item.

Queueing landed as playback queueing, not timeline editing. `VideoPlaybackQueueController` moves from one `VideoPlayableMedia` item to the next after completion, like an usher advancing the next reel. It does not pretend to splice clips, render overlays, or export a final movie. That restraint matters: playback queues and editing compositions look similar on a whiteboard, but they are different beasts once AVFoundation ownership, timing, and export rules show up.

The final additions round out real playback integration seams: audio variants and chapters can be inspected, high-frame-rate and spatial-video characteristics can be detected, custom pixel-buffer output can be created for render integrations, the system audio session has a concrete adapter on platforms that support `AVAudioSession`, and FairPlay/custom resource loading now has an `AVAssetResourceLoaderDelegate` path. The host app still owns license-server policy and key material; the engine just opens the correct AVFoundation door.

### 2026-07-03 — The Projection Booth Gets A Snack Drawer

The engine now has the missing cache/offline layer without turning into an editing suite. Progressive MP4/MOV playback can opt into `ProgressiveVideoCachingPipeline`, which changes the URL scheme before AVFoundation sees it. That makes AVFoundation knock on our door for bytes instead of walking straight to the network.

The key lesson is that video does not politely download from byte zero to the end. Scrub the timeline and AVFoundation may ask for the middle, then the front, then a new middle. The cache therefore works like a careful librarian with torn-out book pages: each byte range is filed at its exact offset, the manifest records which pages exist, and adjacent ranges merge when the missing gap is filled.

Offline support got its own ledger. `VideoOfflineManifestStore` tracks whether a source URL is queued, downloading, available, failed, or cancelled. Progressive files use a background `URLSessionDownloadTask`; HLS uses `AVAssetDownloadURLSession` because Apple packages HLS offline media as a movie package, not as one neat file. `VideoAssetLoader` checks that ledger first, so an available local file wins before the engine reaches for the network.

We still did not build editing, effects, or export. That is intentional. This package now owns playback, caching, and offline reuse. It does not pretend to be a film studio.

### 2026-07-03 — The Byte Hose Learns To Shut Off

The first progressive cache pass worked like ordering a whole sandwich before handing over the first bite: `URLSession.data(for:)` waited for the complete requested range before AVFoundation got anything. That was too chunky for real playback. The resource loader now uses `URLSession.bytes(for:)`, buffers roughly 64 KB at a time, feeds each chunk to `AVAssetResourceLoadingRequest`, and writes the same chunk to disk at its exact byte offset.

Cancellation got a real handle too. AVFoundation can cancel and reissue range requests when a user scrubs, so every loading request now gets a tracked task. When `didCancel` arrives, the task is cancelled and removed from the registry instead of continuing to download bytes for a request nobody wants anymore.

The lesson: a video cache is not just a download button wearing sunglasses. It is a traffic cop for short-lived byte-range promises, and every promise needs a cancellation path.

## Engineer's Wisdom

Good media code has boring ownership. Every observer has one owner, every owner has one teardown path, and teardown can run more than once without drama.

The package also shows a useful boundary pattern: define protocols where the app has opinions. Gateway fallback, Now Playing, persistence, and session events are real app infrastructure, not facts the video engine should import directly.

Tests are best where the machine can be truthful. CI can prove URL validation, policy decisions, transform math, cadence writes, and seek coalescing. It cannot prove that Dolby Vision looks good on a phone or that an Apple TV appears in the route picker, so those live in the device QA checklist.

## If I Were Starting Over...

I would still start with the package boundary and ADRs before building controls. The temptation is to draw the player UI first, but media bugs usually hide in ownership: observers, item replacement, stalls, teardown, and persistence. Build the projection booth before painting the marquee.
