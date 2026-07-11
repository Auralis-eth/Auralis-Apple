# AuraPlayAudioEngine Journal

## 2026-07-01 — The Bench Exists Before The Engine

This package is only the empty bench for future AuraPlay playback work. The current app engine is still doing its job inside Auralis, and no audio engine code has moved here.

The useful decision is restraint. The package and demo app now exist as a clean local place to build later, but there are no playback models, queue types, loaders, AVFoundation wrappers, or tests yet.

Think of it like reserving a workshop before ordering the tools. The door has a label, the demo has a placeholder screen, and the implementation waits until the engine contract is deliberately designed.

## 2026-07-01 — The Engine Gets Its Contracts

Phase 6 arrived with a useful warning label: do not pretend remote audio can magically become gapless AVAudioEngine buffers. So today the package grew from an empty workshop into a labeled tool wall.

The big architectural move is generic media. `NFT.swift` lives in another package, and that is exactly where it should stay. The audio engine now asks for `AuraPlayableMedia`, which is like asking every restaurant supplier to bring ingredients in the same crate. One supplier can be an NFT, another can be a local fixture, another can be a future video-adjacent media object. The kitchen does not need to know the farmer's family tree.

We also wrote down ADR-003: AuraPlay is download-then-play for v1. This is not a philosophical preference; it is physics and API shape. Gapless scheduling, EQ, dynamics, recovery, and offline behavior all become much more honest when the engine owns local readable files instead of chasing a remote stream across the network.

The new contracts are intentionally boring in the best way: session events, cache progress, graph control, gapless scheduling, effects, format factories, Now Playing state, and remote commands. Each one is a hook where a Phase 6 ticket can attach real implementation without smuggling app state into the engine.

Aha moment: the manual QA checklist is not a failure of automation. It is a truth label. CI can prove math, cache eviction, format dispatch, and offline rendering. It cannot truly plug in AirPods, receive a phone call, lock the screen, or press a stem control. Good engineering is knowing which promises are machine-checkable and which need a human holding a device.

## 2026-07-01 — The Engine Starts Making Noise

The contracts now have machinery behind them. The session manager listens for route changes and interruptions, the cache actor turns remote-ish media into local files, and the engine graph finally looks like a small mixing desk: two player decks feeding one mixer, then EQ, then a final gain stage, then the house speakers.

The download cache is the bouncer at the club door. If a track is already inside, playback gets the local URL immediately. If not, it resolves the gateway URL, downloads to disk, writes the little JSON ledger, and evicts the least recently used unpinned files when the room gets too full. Pinned offline tracks and active readers get a wristband and do not get kicked out.

One useful wrinkle: the requested `AVAudioUnitDynamicsProcessor` is not exposed as a public class in the current AVFoundation toolchain. The fix was to use the lower-level Apple Dynamics Processor Audio Unit through `AVAudioUnitEffect`. It is less cozy than a typed wrapper, but it means the graph has a real compressor stage instead of a cardboard prop.

The tests grew teeth too. They now generate real WAV files, open them through `AVAudioFile`, measure approximate loudness, copy through the cache, and verify the topology. That is a much better smoke test than checking file extensions and hoping the oven turns on.

## 2026-07-01 — From Skeleton To Stress Harness

The first pass looked complete from ten paces away, but the acceptance criteria were carrying a flashlight. `localFileWhenPlayable` was just the full-download path wearing a different hat, gapless playback scheduled whole files instead of chunks, recovery listened only when someone manually poked it, AutoMix had the math but not the clock, and Now Playing forgot artwork and ticking elapsed time.

Today’s fix was about turning labels into behavior. The cache now validates status codes, MIME types, empty files, offline misses, and progress. The engine schedules 32,768-frame buffers, converts mismatched formats into the 48 kHz stereo house format, and remembers enough about the current file to rebuild after the audio system changes under it. Recovery now actually observes `AVAudioEngineConfigurationChangeNotification`, which is the audio equivalent of the floor suddenly changing shape while the band is mid-song.

The dynamics node got its real appliance too: Apple’s Dynamics Processor Audio Unit. The typed class name from the ticket does not exist in this toolchain, so the practical route is the component-description API plus parameter IDs. Less pretty, more honest.

AutoMix now owns a timed equal-power ramp, and Now Playing has cached artwork data plus a ticking elapsed-time publisher. The new tests are the kitchen tickets on the rail: cache rejection paths, declared native formats, corrupted MP3 mapping, dynamics parameter wiring, crossfade frame math, and Now Playing timer snapshots. The remaining truth label is still physical QA. CI can prove a lot more now, but it still cannot put AirPods in a human ear.

## 2026-07-01 — The Playback Handoff Learns To Run

The next round went after the sneaky almost-done parts. A cache method named `localFileWhenPlayable` is only honest if it can hand back a file before the entire download finishes, so the downloader grew a progressive path: write bytes into the final cache file, return when the playable threshold is reached, and let a completion task keep filling the tail. Think of it like opening the theater doors once the first act is ready while the crew is still painting the backdrop for act three.

Gapless also stopped being a polite suggestion. Preparing a cached next track now arms the engine, and the final scheduled buffer's `.dataConsumed` callback owns the role swap. That means the transition belongs to the audio scheduling path, not to whoever remembers to call a method at roughly the right time.

AutoMix got a clock, too. It can now schedule the equal-power ramp from the remaining frame count, so crossfade timing is tied to track position instead of wishful wall-clock button pressing. The tests now check the old trap doors directly: progressive readiness before completion, cache finalization after the tail lands, automatic gapless arming, and real generated WAV/AIFF/CAF containers through `AVAudioFile`.

## 2026-07-01 — Partial Files Stop Wearing Fake Mustaches

The latest audit found the kind of bug that makes a playback engine look haunted: a partial cache file could walk up to `localFile(for:)`, flash an index entry, and get treated like a complete download. That is not a cache hit. That is a half-baked cake being served because the plate exists.

The fix was to make cache state matter at the door. Only `.cached` and `.pinned` files can short-circuit as ready. `.partial` files now flow into the resumable range path, where `Accept-Ranges` and `ETag` metadata decide whether the downloader can append the missing tail. The new test recreates the nasty case: one manager writes a partial file, another manager starts later from the same index, and the resumed download must begin at byte 16 instead of silently returning the partial file.

AutoMix got another honesty pass too. The incoming deck now starts at the beginning of the crossfade ramp, then the role swap happens at the end when the outgoing deck is silent. Before that, the code had pretty equal-power math but started the incoming node at the finish line, which is like asking a duet to harmonize after one singer has left the stage.

The fixture coverage also grew up. Declared-format tests are useful for dispatch, but they do not prove real codecs open. Embedded MP3 and FLAC fixtures now decode through the native `AVAudioFile` path, so the format promise has actual audio bytes behind it. The remaining truth label is unchanged: CI can prove package behavior, but a human with a physical device still has to sign off AirPods, calls, Lock Screen controls, background playback, and battery drain.

## 2026-07-01 — Playable Means The Oven Can Actually Bake It

The latest cleanup chased two practical lies that tests were accidentally allowing.

First, `localFileWhenPlayable` could return a partial cache file just because it had enough bytes. That is like letting a customer into the theater because they have a ticket-shaped napkin. The scheduler needs an `AVAudioFile`, so the cache now runs the same `AudioTrackSourceFactory` validation before it calls a partial file playable. The regression test uses random bytes as the fake first chunk and makes sure the cache refuses to hand it to playback.

Second, local-file cache copies were skipping LRU eviction. Network downloads cleaned up after themselves, but file URLs could keep filling the room forever. The local copy path now calls the same eviction policy, and the tests cover the important door rules: oldest unpinned files leave first, pinned files stay, and active readers do not get pulled out from under the engine.

## 2026-07-02 — The Buffer Queue Learns Portion Control

The final ship-readiness pass found a classic audio-engine trap: chunked reads are not enough if you immediately hand every chunk to `AVAudioPlayerNode`. That is like saying dinner is portioned because every dish is on a small plate, then stacking 300 plates on the same table. The controller now keeps a bounded read-ahead window and refills it as `.dataConsumed` callbacks arrive, so long tracks do not quietly turn into memory balloons.

Loudness also got a cleaner package boundary. The engine package still refuses to know about SwiftData, but cache completion now emits a `CachedLoudnessMeasurement` event after measuring the local file. The app can persist that value into whatever model version it owns. The package does the audio work; the app owns the database pen.

Remote commands had their own lifecycle lesson. Registering with `MPRemoteCommandCenter` is not fire-and-forget; every handler token needs a matching cleanup or a recreated publisher can make one button press look like a crowd chanting. The publisher now stores those tokens and removes them on deinit.

The new tests check the behavior that mattered in the audit: cached files emit loudness measurements, and long-track scheduling stays inside the read-ahead cap. Build-for-testing and the full Swift Testing suite are green, leaving only the deliberately human gates: SwiftData integration in the host app and physical-device QA.

## 2026-07-02 — The Audit Stops Taking Props At Face Value

The readiness review found four cardboard cutouts hiding on stage. The graph description was a poster of the graph, not the graph. Gapless had a nice final-buffer handoff, but no recorded render-frame boundary. AutoMix was listening to a wall clock instead of the player timeline. Underrun recovery waved a flag but did not actually tell the scheduler where to pick the song back up.

Today those props got replaced with load-bearing pieces. The engine now reports live connection state, prepared gapless transitions remember the exact frame boundary they are aiming at, AutoMix computes fade progress from the rendered frame position, and progressive underrun recovery pauses, waits for more bytes, reschedules the saved frame, then publishes recovery. That is the difference between a stage manager saying "the scene changed" and actually moving the scenery.

The tests got less gullible too. AAC and ALAC now use generated encoded fixtures instead of WAV files wearing fake name tags. Now Playing gets a system-center readback when the host supports echoing that state, and remote skip intervals are checked against `MPRemoteCommandCenter`. The truth label remains: CI proves package mechanics; physical QA still owns real AirPods, calls, Lock Screen behavior, and audible gaplessness.

## 2026-07-02 — One Door, One Downloader

The progressive cache path had a race hiding in plain sight. `localFile(for:)` had a bouncer for in-flight downloads, but `localFileWhenPlayable` was letting every caller walk directly to the same destination file with a paint bucket. Four callers asking for the same track could start four progressive downloads, all writing to the same cache path. That is not enthusiasm; that is a race condition with a soundtrack.

The fix was to put progressive playable requests behind the same in-flight gate as full downloads, then teach the cache that a recorded `.partial` file can be reused by `localFileWhenPlayable` after it passes the actual audio-open validation. Now the first caller opens the door, concurrent callers share the same handoff, and late callers reuse the playable partial while the completion task keeps filling in the tail.

The regression test is deliberately rude: it fires four concurrent same-media requests at an actor-backed downloader and expects one playable download, one URL, and no fake cached state until the completion task finishes. We also added CI-checkable coverage for interruption recovery flowing through `MockAudioSessionManager.send` and for independent remote-command publisher streams. Physical device QA still owns the real-world hardware promises, but this bug no longer needs a human ear to catch it.

## 2026-07-02 — Cache Hits Need ID At The Door

Today's audit fix chased two cache lies that would have been painful in production.

First, a download could show up short, wave a `Content-Length` receipt, and still get written into the ledger as fully cached. That is like signing for ten boxes, seeing seven on the loading dock, and telling the kitchen inventory is perfect. Complete HTTP-backed cache writes now compare the bytes on disk against the server-declared full length when that length exists. Progressive partial playback still gets its early handoff, but final cache completion has to prove the whole file arrived.

Second, the cache key was using only the media ID. IDs are useful, but they are not a fingerprint. If the same NFT-shaped object changes source URL or declared format, the cache now treats the old row as stale instead of serving yesterday's audio in today's costume. Cache entries store the original source URL and normalized format, in-flight downloads share only when that fingerprint matches, and replaced entries clean up old filenames when format changes move the file.

The tests now cover both traps directly: a fake downloader lies about `Content-Length` and must be rejected, and a same-ID media object with a new source must replace the cached bytes instead of reusing them. The device QA checklist still belongs to a human with hardware, but these two cache correctness bugs are now machine-checked.

## 2026-07-02 — The Shipping Surface Stops Carrying Test Props

The next cleanup pass was about not shipping scaffolding as architecture. `MockAudioSessionManager` was handy, but it was standing in the production target wearing a library badge. Test doubles belong in tests unless they are intentionally supported API, so the mock moved into the Swift Testing file and became an actor. The recovery tests still get deterministic session events, but the public package surface is cleaner.

The other fix was a concurrency honesty pass. `NowPlayingPublisher` and `AutoMixController` both promised `Sendable` while holding mutable state. That is like saying a shared notebook is safe because everyone is polite. Now their mutable snapshot/task/ramp state goes through serial queues, while the existing public API stays intact. The tests add concurrent update pressure so future edits have a guardrail.

MediaPlayer tests got their own quiet room. Snapshot tests opt out of writing to the process-wide Now Playing center, and the real system-center / remote-command checks live in a serialized suite. That keeps Swift Testing parallelism useful without letting global OS state leak between unrelated tests.

Finally, `CacheKey` learned what to do when an ID sanitizes down to nothing. Instead of creating an empty filename, it falls back to a deterministic byte-hex key, with `media-empty` for the truly empty string. The cache door now has a label even when the incoming ID is just punctuation soup.

## 2026-07-02 — Tests Stop Racing The Stopwatch

The final review run caught a test-quality smell instead of a production bug. `localFileWhenPlayable` was proving the right behavior, but it did it by racing a 300 ms tail delay against the machine scheduler. On a busy run, the method still returned before the cache was complete, but the stopwatch made the test look guilty.

The fix was to ask the fake downloader the real question: "has the completion task finished yet?" A tiny actor probe now marks when the tail write completes. The test asserts the playable URL returns while that probe is still false, then waits for the cache to become fully cached and sees the probe flip true. Same story, fewer timing theatrics.

## 2026-07-02 — Visualizers Are A Side Channel, Not An Export Truck

The latest product boundary decision keeps export out of the playback package. Export would mean saving processed audio, trimmed files, concatenated files, or mixdowns. That is a different job from AuraPlay's current mission: make cached NFT audio play cleanly, recover well, and tell the app useful facts.

Analysis output is the right next layer. Think of it like a small telemetry booth next to the stage: it watches the mixer, reports RMS and peak levels, maybe later spectrum bins, and lets the UI draw visualizers without asking the engine to manufacture a new audio file. That keeps the package honest. Playback stays playback, the app gets visual energy, and nobody accidentally signs us up for a mini DAW.

The README now states that play-as-you-download means progressive local-file playback. The engine still plays a local `AVAudioFile`; the cache can simply return that file before the download tail is finished once the partial is actually playable. That distinction matters because it preserves the download-then-play architecture while still giving the UI a faster start.

## 2026-07-02 — The Telemetry Booth Opens

Visualizers moved from roadmap sketch to package API today. The engine now has a small side-channel that watches the track mixer and emits `AudioVisualizationFrame` values with per-channel RMS and peak levels. It is intentionally not an export pipeline and not a second audio engine. It is more like a VU meter taped beside the mixing desk: it observes the show, reports the energy, and leaves the speakers alone.

The important concurrency detail is that the tap owns the realtime callback, while the public handoff is just value snapshots through an `AsyncStream` with newest-frame buffering. Starting a new stream replaces the old tap, stopping removes it, and stream termination has a generation token so yesterday's cleanup cannot unplug today's meter.

The tests stay honest too. CI checks the RMS/peak math, callback-pressure clamping, and graph lifecycle, but it does not pretend to validate a beautiful waveform on a real screen. That belongs to the host app and, eventually, device QA.

## 2026-07-02 — The Cache Stops Serving Raw Dough

The ship-readiness review found the kind of edge case that only appears after the happy path has started looking respectable: the cache could file a completed download into the ledger before proving `AVAudioFile` could actually open it. Byte counts and MIME types are useful, but they are not music. They are the grocery receipt, not the meal.

Now every complete cache write, local or remote, has to pass the same audio-source validation before it gets stamped as `.cached`. Corrupt local files and corrupt `audio/wav` HTTP downloads get rejected at the door, and the tests make sure they do not leave fake cache hits behind.

The progressive path also got a better traffic cop. A playable partial and its completion tail are now tracked as one in-flight operation: callers asking for early playback get the first decodable file, while callers asking for the full local file wait for the same completion task instead of starting a second writer against the same path. That closes the race where two workers could both decide they owned the paintbrush.

One subtle timing bug was about the word "playable." Some containers are not decodable the moment the byte threshold is crossed, so the cache now keeps checking until the partial really opens or the completion/failure settles the matter. Finally, gapless boundary planning learned to speak two clocks: recovery seeks in source-file frames, while scheduled render boundaries are converted into the engine's 48 kHz timeline. Same song, fewer unit-conversion traps.

## 2026-07-02 — Cache Hits Get Re-Carded

A later ship-readiness pass found one more bouncer problem: once a completed file made it into the cache ledger, future lookups trusted the ledger and the file's existence. That works until a disk write, external cleanup, or unlucky corruption turns the cached file into a costume with no actor inside it.

Complete cache hits now get re-carded before reuse. The cache reopens the local file through the audio-source validation path; if it fails, the entry and its files are removed, `isCached` returns false, and `localFile(for:)` falls through to the normal recache path. The new regression test corrupts a completed cache file after indexing, then proves the manager refuses the stale hit and restores a real audio file from the source.

The format promise also got more precise. Generated AAC-in-M4A coverage stays, but raw `.aac` is no longer advertised as a default native extension until a real ADTS/raw AAC fixture proves it. And the MediaPlayer tests stopped pretending `.serialized` guarded process-wide state; one MainActor test now owns the system-center and remote-command checks in a single room.

## 2026-07-02 — The Timer Lets Go And Pins Stay Pinned

Two small bugs had the same personality: they both forgot who owned the room.

The Now Playing elapsed timer used a weak capture, then immediately grabbed `self` and carried it into an infinite sleep loop. That is like saying the door is unlocked while leaning against it forever. The task now sleeps with only the tick interval in hand, then briefly reacquires the publisher for each update. If the caller drops the publisher without calling `stopElapsedTimeUpdates()`, the publisher can still leave the building.

The progressive cache had the opposite problem. A media item could ask to be pinned, but the progressive completion path filed it as ordinary cached audio. Full downloads remembered the wristband; progressive downloads lost it at coat check. Completion now records the same pinned intent as the other cache paths, and the regression test proves it the only way that matters: after eviction pressure, the pinned progressive track is still there and the unpinned trigger is gone.

## 2026-07-02 — AutoMix Learns To Wait Without Grabbing The Conductor

AutoMix had the same lifetime smell as the Now Playing timer, just wearing headphones. The scheduled crossfade task weak-captured the controller, then immediately held it while waiting for the render frame to reach the ramp start. If playback progress stalled, dropping the controller would not actually release it until someone remembered to cancel the task.

The wait loop now carries only the collaborators it truly needs: the engine controller, scheduler, and curve. The `AutoMixController` is reacquired only to clear bookkeeping after the task finishes. That keeps the crossfade machinery running on its own clock without turning task storage into accidental ownership.

The new regression parks a crossfade a minute in the future, gives the task enough time to enter its sleep loop, then releases the controller. If the task ever starts holding the controller across polling sleeps again, the weak reference test will catch it.

## 2026-07-03 — The Engine Stops Asking The File System Twice

A WWDC media-loading audit gave us a useful reminder: synchronous media inspection is still synchronous even when the file is local and the code looks harmless. The gapless boundary path was reopening the current `AVAudioFile` just to ask for length and sample rate after the file had already been scheduled. That is like the stage manager stopping mid-scene to run back to the filing cabinet for a cue sheet already in their hand.

The controller now stores source length and sample rate on the scheduled stream and plans render-frame boundaries from that in-memory metadata. The regression test proves the point by deleting the original file after scheduling; the open stream can still plan the handoff because it no longer needs a second trip through the filesystem.

The resumable downloader got the same treatment in byte form. Appending a ranged tail used to read the whole temporary file into one `Data` before writing it to the partial cache file. Fine for a tiny fixture, rude for real audio. It now streams the append through a bounded buffer, so a long resumed download does not become a surprise memory balloon.

## 2026-07-07 — AirPlay Gets Its Own Highway

The WWDC AirPlay session forced a useful piece of honesty into the package: our custom `AVAudioEngine` graph is a great workshop, but it is not the system highway Apple built for enhanced AirPlay buffering. EQ, dynamics, visualizers, and gapless scheduling all belong in that workshop. HomePod robustness, AirPlay reconnects, and wireless CarPlay responsiveness want `AVQueuePlayer` unless we are ready to build a custom sample-buffer renderer.

So AuraPlay now has two doors. The old door is still the custom engine: cached local files walk through the mixer, EQ, dynamics processor, and visualization tap. The new door is `AirPlayQueuePlayerController`, an opt-in `AVQueuePlayer` route that shares Now Playing and remote command plumbing but lets the system do the AirPlay-heavy lifting. Think of it like having both a studio control room and a dedicated express lane to the whole-home speaker system.

The audio session also learned the missing etiquette: long-form playback now asks for `.longFormAudio` route sharing policy instead of only saying "playback plus AirPlay, please." The demo grew an AirPlay picker and a route-mode switch, while ADR-004 writes down the tradeoff so future us does not accidentally expect HomePod magic from the wrong route.

The catch remains physical QA. CI can prove the queue starts at the right item and reacts to remote commands. It cannot walk out of Wi-Fi range with a HomePod playing in the kitchen. That test still needs a human, a real speaker, and probably a slightly suspicious neighbor.

## 2026-07-07 — AirPods Listen For Intent, Not Vibes

The AirPods session added a different kind of lesson: system audio features are partly about telling the truth. AirPods automatic switching listens for signals like Now Playing and input audio activity. If AuraPlay publishes every beep, preview, placeholder, and silent keepalive as "now playing," the system starts making route decisions from bad gossip.

So the rule is now written down: Now Playing is only for real long-form media. A track can wear the badge. A notification chime cannot. A silent loop after pause is not clever engineering; it is the app pretending the show is still running after the band packed up.

This also keeps the feature boundaries clean. Press to Mute belongs to calls, live rooms, and microphone pipelines, not to a playback package with no uplink audio. Spatial Audio is real future work, but the sane first door is the `AVQueuePlayer` route we already added, not an ambisonic side quest inside the default engine graph.

The best part is that this mostly costs discipline, not machinery. Respect the route the user chose, publish honest Now Playing state, keep chimes out of the media engine, and test AirPods switching on actual devices. The operating system can do a lot when we stop feeding it costume jewelry and call it telemetry.

## 2026-07-07 — Done Means The Boundary Has A Door

The latest cleanup turned a fuzzy "future work" cloud into a sharper release contract. Host integration now has three loud gates: wire the package into real playback flows, set `AVInitialRouteSharingPolicy` to `LongFormAudio`, and enforce Now Playing honesty with no chimes, previews, placeholders, or silent keepalives.

Spatial Audio and Press to Mute also got their Phase 6 definitions. Spatial Audio is not secretly inside the custom graph; the first real path is the `AVQueuePlayer` route because that is where the system can help. Press to Mute is not secretly in the playback engine either; no microphone means no uplink mute state to manage. If the app later grows calls or live rooms, that feature gets its own front door and its own QA.

## 2026-07-07 — ASAF Is A Movie Set, Not A Guitar Pedal

The ASAF/APAC session drew a bright line around future immersive audio support. Apple Spatial Audio Format is not a new coat of paint on MP3. It can carry Higher Order Ambisonics, objects, and metadata that the platform renderer adapts to listener and object movement. Treating that as a plain cached file inside the Phase 6 engine would be like flattening a film set into a postcard and claiming the actors are still walking around.

So the future path is system first: if AuraPlay ever gets ASAF/APAC assets, they go through `AVQueuePlayer` / `AVPlayer` before anyone proposes custom decode. APAC streaming, stereo compatibility fallback, and spatial playback QA all belong to that route. The custom engine keeps doing what it is built for: local-file playback, effects, visualization, gapless scheduling, and recovery.

Authoring is also outside the fence. Pro Tools plugins, Fairlight, Broadcast Wave, APAC encoding, and immersive media export are production-pipeline jobs. AuraPlay is a playback package unless the product deliberately becomes an authoring tool.

## 2026-07-07 — Spatial Audio Gets A Switchboard, Not A Fake Theater

The Spatial Audio implementation finally landed where it belongs: in the system route. `AirPlayQueuePlayerController` now has an `AuraSpatialAudioPolicy` that maps to `AVPlayerItem.allowedAudioSpatializationFormats`, so the host can allow mono/stereo, multichannel, both, or none without pretending the custom engine knows how to spatialize a scene.

The audio session got its side of the handshake too. `AudioSessionManager` can advertise multichannel content, report whether the current route has Spatial Audio enabled, and publish spatial capability changes when routes or user settings move. That gives the host UI a clean signal: show availability, do not force the user's Control Center choice.

The custom engine stays honest. It still does local files, EQ, dynamics, visualizers, gapless scheduling, and recovery. It does not get a cardboard spatial theater bolted onto the side. Real multichannel HLS, DRC/dialnorm metadata, and device verification remain content and QA work.

## 2026-07-07 — Voice Processing Belongs To The Microphone Room

The voice processing session was useful precisely because it did not belong in AuraPlay. Apple's voice APIs are for voice chat: echo cancellation, noise suppression, automatic gain, other-audio ducking, muted talker detection, and platform mute behavior. AuraPlay has no microphone and no uplink, so adding those APIs here would be like installing a conference-room intercom in a record player.

The boundary is now explicit. A future voice feature should prefer `AVAudioEngine` voice processing mode, reach for `AUVoiceProcessingIO` only when it needs low-level I/O control, and own its own mute, ducking, muted-talker, privacy, and device QA. If voice chat overlaps with AuraPlay music, the voice module decides how much the music ducks. The playback engine keeps playing media and does not pretend to be a call stack.

## 2026-07-10 — The Release Review Found The Trapdoors

The package looked calm in the simulator, but the readiness review poked exactly where audio code likes to lie. Gapless was planning a boundary in "frames left" and handing it to `play(at:)` like an absolute render timestamp. That is the kind of bug that passes a math test and then makes two songs sing over each other on a real device. The fix is to schedule the inactive deck at the current node render time plus the remaining rendered frames, while preserving the old non-running debug behavior for tests.

The cache learned another door rule: a partial file can be playable without being complete, but it cannot be pinned as complete. `pin` now forces the full-file path to finish before it stamps the entry as pinned, which keeps a truncated-but-decodable prefix from becoming a permanent offline "album."

The event streams got promoted from a single shared straw to a small broadcast board. Cache progress, loudness measurements, session events, recovery events, and remote commands now give each subscriber its own `AsyncStream`, so the UI and recovery coordinator can both listen without quietly stealing values from each other.

AirPlay got the boring-but-important housekeeping too. When `AVQueuePlayer` naturally advances at item end, AuraPlay now trims its queue bookkeeping and republishes Now Playing for the new track. The lock screen should not keep announcing yesterday's song just because the system player moved on by itself.

AutoMix also stopped mixing frame languages. The ramp now reads the engine's rendered frame clock and render sample rate instead of blending source frames with a hardcoded 48 kHz ruler. That sounds like accountant work, but it is the difference between a graceful crossfade and a duet arriving late by nine percent.

The machine checks are better now: library build is green, Xcode build-for-testing is green, and regressions cover the new doors. The human gate remains exactly where it should be: physical-device QA for audible gaplessness, AirPlay, interruptions, background playback, Lock Screen controls, accessories, and battery behavior.
