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

### 2026-07-11 — Cancel Means Cancel, Even When The System Calls Back Twice

Two shipping bugs showed why media code needs receipts for its receipts. Cancelling an offline download wrote `.cancelled`, then URLSession politely knocked again with `NSURLErrorCancelled`; the delegate treated that second knock like a real failure and overwrote the ledger with `.failed`. Progressive files and HLS packages now share one completion mapper, and the manifest refuses to let a late failed record smear over a cancelled one.

PiP had a similar confidence problem. The coordinator tried to start Picture in Picture after the app had already entered the background, which is like asking the usher to open the side door after the theater has been locked. The engine now flushes position on background and relies on AVKit's automatic inline PiP path that `PictureInPictureController` already enables. Device QA still has to prove the system behavior, but the code no longer promises an impossible manual rescue.

### 2026-07-11 — The Snack Drawer Gets A Bouncer And A Budget

The follow-up hardening pass handled the smaller-but-real video engine potholes. Download managers now ignore duplicate starts for a URL that is already active, which keeps two background tasks from racing toward the same file like two stagehands carrying the same ladder through opposite doors. They also expose a background-session handoff method, so the host app has a documented place to park Apple's completion handler until URLSession says all background events have arrived.

The cache and manifest stores stopped reading the whole pantry during construction. Initializers now set the address on the door; the first actor operation does the disk work. That keeps a view or assembly from blocking just because it created a store. The progressive cache also has a 2 GB default budget and evicts older entries after writes, because a cache without a ceiling eventually becomes a storage leak with better branding.

Two UI/runtime details got tightened too. The 60fps player tick now uses the fact that AVPlayer is already calling on `.main` instead of scheduling a new main-actor task sixty times a second. And `PlayerContainerView` documents that `onLayerReady` fires on updates, so hosts know to reuse PiP controllers instead of rebuilding one every time SwiftUI redraws the screen.

### 2026-07-11 — The Projection Booth Stopped Hoarding Tickets

The shipping review found three bugs that all rhymed: the engine was accepting media bookkeeping at face value when AVFoundation needed stricter contracts. The resource loader wrote a server MIME type like `video/mp4` into a field that wants a UTI such as `public.mpeg-4`, which is like handing the projector a restaurant menu when it asked for a reel label. The loader now translates MIME strings through `UTType` and falls back to the file extension when a server gives us mush.

The event stream had a different leak. A 60fps progress tick is useful for a custom scrubber, but an unbounded `AsyncStream` turns into a ticket drawer that never gets emptied if nobody is standing there collecting tickets. `VideoPlayerController.events` now keeps only the newest buffered events, and the README calls out the important footnote: `AsyncStream` is single-consumer, so the integration coordinator and queue controller cannot both sip from the same stream and expect to see every event.

Offline downloads got the janitor pass too. Progress observers now unregister on termination, terminal records finish their streams, successful tasks leave the task registry, and delegate progress skips unknown zero-progress updates instead of letting a stale callback overwrite an available record. The lesson is plain media-engine hygiene: anything that ticks, streams, or downloads needs a matching way to stop being remembered.

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

### 2026-07-03 — Spatial Video Gets An Honest Stage Manager

The WWDC spatial media guidance exposed a subtle trap: detecting a spatial video is not the same as being able to present it with the full visionOS spatial experience. A custom `AVPlayerLayer` is still our hardworking stage for Aura controls, PiP, overlays, and normal playback, but it is not the Photos app's spatial portal.

`VideoSpatialPlaybackPolicy` now names the promise clearly. Custom-layer playback is an inline 2D fallback for spatial assets, `AVPlayerViewController` fullscreen is a stereo route, and the full spatial presentation belongs to a host-provided system presenter such as Quick Look on visionOS. That is the difference between putting a 3D postcard on a screen and opening the right door into the memory.

Detection also learned to ask the newer bouncer first. `AVAssetPlaybackAssistant` can report `.spatialVideo` for local assets, and the older track-characteristics check still stays in the line as a fallback. If either reliable path says the asset is spatial, the engine believes it.

### 2026-07-03 — The Stage Manager Learns There Are More Stages

The next immersive playback session widened the map. Spatial video is only one stop. visionOS now has stereo 3D, spatial video, Apple Projected Media Profile for 180/360/wide-field video, and Apple Immersive Video. Treating all of that as one boolean would be like labeling every venue from a coffee shop to an arena as "has chairs."

`VideoImmersiveMediaProfile` now gives the engine better vocabulary: standard 2D, stereo 3D, spatial video, APMP, Apple Immersive Video, and unknown immersive. `AVAssetPlaybackAssistant` is the first scout because it knows about options like `.stereoVideo`, `.spatialVideo`, `.appleImmersiveVideo`, and `.nonRectilinearProjection`; track characteristics remain the fallback scout for older clues.

The boundary stayed clean. `PlayerContainerView` is still the custom Aura screen. AVKit immersive transitions with `AVExperienceController`, Quick Look previews, and RealityKit progressive/full/mixed immersive spaces are host-owned stages. The package now defines a handoff request and a policy map, but it does not sneak a whole theater into the projection booth.

### 2026-07-07 — The Map Finally Includes visionOS

The package talked about visionOS like a travel guide that forgot to print the country on the map. That is fixed: `Package.swift` now declares iOS 26, macOS 26, and visionOS 26 support. This does not magically complete headset QA or build the host-owned Quick Look, AVKit, or RealityKit adapters, but it makes the package boundary honest for the platforms its immersive policy is designed to serve.

### 2026-07-07 — The Broadcast Truck Is Not The Living Room Player

The live immersive production session added a useful guardrail. Apple Immersive Live production is not just "play a bigger movie." It is a broadcast kitchen with separate stations: SMPTE 2110-22 carries streamed ProRes video, 2110-30 carries ASAF PCM audio, and 2110-41 carries per-frame JSON metadata. When that stream is recorded, the point is to copy the ProRes frames into MOV without a decode/re-encode lap, preserve audio as PCM, and turn the JSON into synchronized MEBX metadata with Immersive Media Support.

That belongs beside AuraPlayVideoEngine, not inside it. Our package is the living room player: load resolved media, inspect capabilities, choose an honest presentation route, cache/offline when appropriate, and hand immersive experiences to the host. A future production-tools package would be the broadcast truck: ingest, route, record, replay, and make sure `kVTProjectionKind_AppleImmersiveVideo` writes the right `vexu` passport stamp so other tools recognize the file as Apple Immersive Video.

### 2026-07-07 — Multiview Gets A Traffic Controller

The multiview playback session turned into real package code. The important lesson was not "make the player bigger"; it was "stop making one player pretend it owns the intersection." `VideoMultiviewCoordinator` now sits above multiple `VideoPlayerController` instances and handles the crossing guard jobs: synchronize players through `AVPlaybackCoordinationMedium`, tell AirPlay which participant should win the single external screen, tell non-mixable audio routes which participant should speak, and mark primary/secondary streams with network priority hints.

The single-player controller stayed single. That matters. A queue is one projector with many reels; multiview is several projectors showing related angles at the same time. Mixing those two would make every future playback bug harder to reason about. The coordinator gives us a place for multi-player rules without teaching the projectionist to run the whole stadium.

### 2026-07-07 — The Theater Belongs To The Host App

The visionOS theater-environment session sharpened another boundary. AuraPlayVideoEngine can say, "this asset deserves AVKit fullscreen, a portal, or a RealityKit scene," but it should not start decorating the theater. Custom docking regions, media reflections, environment probes, passthrough tint, reverb presets, and immersive environment picker entries are set design. They belong to the host app's `ImmersiveSpace`, Reality Composer Pro project, and AVKit adapter.

SharePlay has the same split. Media timing sync belongs to the player playback coordinator; shared environment state belongs to `AVPlayerViewController.groupExperienceCoordinator`. That is a useful two-lane road: the engine keeps handing the host clean playback intent, while the host decides where the screen hangs, what the room sounds like, and whether everyone in a GroupActivity sees the same environment.

### 2026-07-10 — Remote Skip Found The Wrong Door

The release review caught a beautifully Swift-shaped trap: remote skip commands looked implemented, but the methods lived only in a protocol extension. When the remote dispatcher held the transport as an existential, Swift walked through the extension default instead of the video coordinator's custom skip path. The result was a skip wearing a scrub costume: zero-tolerance seek behavior where the video engine expected skip tolerance.

The fix was to put `skipForward(by:)` and `skipBackward(by:)` on the actual media transport protocol while keeping the defaults. That turns the methods into real dispatch requirements without breaking simpler transports. The same pass tightened the booth doors: teardown now finishes the event stream, queue/coordinator observation tasks no longer keep their owners alive forever, and progressive caching refuses to write HTTP error pages or ignored-range responses into media files.

A follow-up made the lifecycle contract explicit: teardown is terminal. Reloading a torn-down controller now fails with a typed error instead of quietly updating state while every event falls into a finished stream. The cache ledger also learned three shipping habits: store local file paths relative to the offline manifest directory, use bookmark data for system-managed HLS packages outside that directory, and refuse stale nonzero `.downloading` progress after an `.available` record has landed while still allowing a fresh redownload start.

The gateway fallback timer also moved out of the general observation task bucket. There is now one cancellable fallback check at a time, so repeated stalls do not stack delayed tasks until `stop()`.

The lesson is a good one for Swift protocols and media lifecycles: extension defaults are convenience, not polymorphism, and a closed projection booth should stay closed unless you build a real reopening ceremony.

### 2026-07-12 — The Loader Learns To Count Past The Edge Of The Map

A pre-ship review found two real hazards in the progressive resource loader. First, AVFoundation reports requests-to-end with `requestedLength == Int.max`, and our range math added that to the offset — a guaranteed Swift overflow trap the moment a nonzero-offset request-to-end arrived. The loader now resolves a concrete window from the known content length when it has one and otherwise sends an honest open-ended `bytes=offset-` range; every remaining piece of `offset + length` arithmetic is overflow-checked and degrades instead of trapping.

Second, the loader treated a 200 reply to a range request as a fatal protocol violation. Strict, but wrong for our audience: an NFT gateway that ignores Range headers would make every progressive MP4 unplayable, because the pipeline rewrites all of them into the cache scheme. The loader now accepts the 200, treats the stream as starting at byte zero, caches everything it receives at the correct offsets, forwards only the requested window to AVFoundation, and cancels the transfer once the window is served. The strict path stays strict where it matters — HTTP errors still fail the request.

The same pass fixed a speed-control side effect (`setSpeed` no longer starts a paused player by assigning a nonzero rate; the stored speed applies on the next play), persisted content-information probes so requests-to-end can resolve without refetching, made the offline manifest store retry a failed first read instead of silently treating the manifest as empty, added a precondition so `HLSVideoOfflineDownloadManager` fails with an actionable message when handed a non-background session configuration, and brought the README's `VideoPlayableMedia` sketch back in line with the real protocol.

The lesson: validate the world you actually stream from, not the world the RFC promises. Servers lie about ranges; the player still has to play.

## Engineer's Wisdom

Good media code has boring ownership. Every observer has one owner, every owner has one teardown path, and teardown can run more than once without drama.

The package also shows a useful boundary pattern: define protocols where the app has opinions. Gateway fallback, Now Playing, persistence, and session events are real app infrastructure, not facts the video engine should import directly.

Tests are best where the machine can be truthful. CI can prove URL validation, policy decisions, transform math, cadence writes, and seek coalescing. It cannot prove that Dolby Vision looks good on a phone or that an Apple TV appears in the route picker, so those live in the device QA checklist.

## If I Were Starting Over...

I would still start with the package boundary and ADRs before building controls. The temptation is to draw the player UI first, but media bugs usually hide in ownership: observers, item replacement, stalls, teardown, and persistence. Build the projection booth before painting the marquee.
