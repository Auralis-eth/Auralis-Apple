# AuraPlay Phase 10 Player UI Implementation Plan

## Summary

Phase 10 builds the full-screen AuraPlay Now Playing experience presented from the Phase 9 mini-player. The player is a SwiftUI presentation layer over Phase 8 playback orchestration and the Phase 6/7 audio/video engines. It observes one playback state, sends commands through one command surface, and never owns playback authority itself.

The work is not a visual polish pass over the existing audio Now Playing screen. The current codebase has three useful but separate foundations:

- `AuraPlayMiniPlayerView` presents the current `AuraPlayNowPlayingView` sheet.
- `AuraPlayNowPlayingView` is an audio-forward surface built around `AuraPlayPlaybackPresenting`.
- `AuraPlayVideoWireframeView` proves many video controls with `PlayerContainerView`, PiP, route picking, subtitles, speed, gestures, and video chrome.

Phase 10 should unify those capabilities behind a player-specific presentation and command adapter that can read the Phase 8 orchestrator, expose engine-specific capabilities, and keep the SwiftUI views free of playback logic.

## Implementation Status — Implemented (with divergences)

**Status: implemented on branch `music-mini-app`.** The sections below describe the *pre-implementation* design and are retained for rationale. The full player is built in the `MusicFeature` package under `Presentation/Player/` and is presented from `AuraPlayMiniPlayerView`.

As-built confirmations:

- Player UI: `AuraPlayPlayerView`, `AuraPlayPlayerPresentation`, `AuraPlayPlayerCommanding`, `AuraPlayUpNextSheet`, `AuraPlayAudioControlsSheet`, `AuraPlayVideoControlsOverlay`, `AuraPlayPlayerGestureLayer`, `AuraPlayPlayerContextMenuBuilder` all exist in the package.
- Shared `SeekCoalescer` is placed in `AuraPlayMediaCore` (the preferred engine-neutral placement from "Shared seek coalescing package choice").
- Queue UI targets `QueueEntry.id` identity; Up Next duplicate-entry behavior is covered by tests.
- P10-009 snapshots live in `LibraryAndPlayerSnapshotTests` (audio/video player, Up Next duplicates).

Divergences from this plan (intentional, not defects):

1. **Adapter placement.** The plan prescribed an app-target folder `Auralis/Auralis/MusicApp/AuraPlay/Player/` with `AuraPlayPlayerAdapter`/`AuraPlayPlayerCommandAdapter`/etc. mapping the app-private `PlaybackOrchestrator` into the presentation contract. **That folder and those adapters were not created.** Instead, a package-level generic adapter `AuraPlayPlaybackPlayerAdapter<Presenter: AuraPlayPlaybackPresenting>` (in `Presentation/Player/AuraPlayPlaybackPlayerAdapter.swift`) bridges the *existing* `AuraPlayPlaybackPresenting` presenter into `AuraPlayPlayerCommanding`, and is constructed inline in `AuraPlayMiniPlayerView` when the player sheet is presented. Net effect: the player is driven through the existing Phase-8 presenting protocol rather than a new app-target orchestrator→presentation adapter. The "Code Placement" and "Required Foundations §1" sections below do not match reality on this point.
2. **Snapshot baselines re-recorded.** The originally committed `LibraryAndPlayerSnapshotTests` player baselines were bad (dark-text-on-dark, illegible) — not regressions in current code — and were re-recorded on the local host (Xcode-beta, iOS 27 SDK). They now pass deterministically. Note: `light` and `dark` player variants render identically because the player forces its own dark stage regardless of `colorScheme`; those variants are redundant and a candidate for cleanup.

## Current Baseline

### Existing player-facing UI

`MusicFeature/Sources/MusicFeature/Presentation/Playback/AuraPlayMiniPlayerView.swift` currently owns `showNowPlaying` and presents `AuraPlayNowPlayingView(player:)` as a sheet. It already models the mini-player-to-full-player entry point, but it is still coupled to `AuraPlayPlaybackPresenting` rather than the Phase 8 orchestrator adapter expected by Phase 9/10.

`MusicFeature/Sources/MusicFeature/Presentation/Playback/AuraPlayNowPlayingView.swift` already provides artwork, progress, transport controls, queue sheet entry, recently played rows, and audio tuning integration. It also has local seek-drag state and calls `auraPlaySeek(to:)` on editing end. Phase 10 can reuse the component lessons, but the new scrubber needs a shared coalescing path and content-type awareness.

`Auralis/Auralis/MusicApp/AuraPlay/Presentation/AuraPlayVideoWireframeView.swift` has the richest video prototype. It hosts `PlayerContainerView`, manages PiP, route picker, subtitles, speed, zoom, double-tap seek, and video chrome. Phase 10 should pull these capabilities into a reusable video branch instead of keeping the production player and video room as separate control surfaces.

### Existing playback/orchestration code

`Auralis/Auralis/MusicApp/AuraPlay/Services/AuraPlayPlaybackOrchestration.swift` defines `PlaybackOrchestrator`, `OrchestratorState`, `EngineKind`, `EngineArbiter`, and core commands:

- `togglePlayPause()`
- `pause()` / `resume()` / `stop()`
- `skipToNext()` / `skipToPrevious()`
- `seek(to:)`
- `restorePaused(item:position:)`
- `restoreMostRecent(resolveMedia:)`
- repeat and shuffle setters

`AuraPlayPlaybackQueue` already has `QueueEntry.id`, `currentEntryID`, `history`, `remove(entryID:)`, and `reorder(entryID:toIndex:)`. This is the correct identity model for Up Next. Phase 10 must not reintroduce index-based or `MediaItem.id`-based queue mutation.

`AuraPlayVideoEngine` already provides:

- `PlayerContainerView` with the shared `AVPlayerLayer` callback needed by PiP.
- `ChaseTimeSeekCoordinator`, a small actor that chases the latest target.
- `PictureInPictureController` with `PiPState` and restore callback.
- `VideoRoutePickerView`, backed by `AVRoutePickerView` with `prioritizesVideoDevices = true`.
- `SubtitleTrackManager` with legible and audio-description track discovery.
- `PlaybackSpeedController` and `PlaybackSpeedOption` with the persisted speed key.

`MusicFeature` already exposes audio tuning presentation values: EQ preset, normalization state, crossfade duration, custom EQ gains, and related commands. Phase 10 should keep using that shape where it matches Phase 6 instead of creating a second settings model.

## Non-Negotiable Invariants

1. Player UI is state-observing and command-issuing only.
2. `PlayerView` holds no local play/pause, queue, or current-item authority.
3. Audio and video render from the same current orchestrator item.
4. Audio-only controls are structurally absent for video content.
5. Video-only controls are structurally absent for audio content.
6. Video uses the existing `PlayerContainerView` and shared `AVPlayerLayer` used by PiP.
7. Dismissing the full player never pauses, stops, or clears playback.
8. Scrubber drag and double-tap seek share one `SeekCoalescer`.
9. Queue mutations target `QueueEntry.id`, never array position as identity and never `MediaItem.id`.
10. Reduce Motion changes matched transitions, gesture feedback, and auto-hide animation into simple fades.
11. VoiceOver has explicit alternatives for every gesture-only action.
12. Text over video always has a scrim or equivalent contrast layer.
13. Liquid Glass effects are grouped and limited for performance, using `GlassEffectContainer` and `glassEffect` where available.

## Code Placement

Phase 10 crosses package and app boundaries. The rule is simple: reusable presentation contracts and SwiftUI components belong in packages; live orchestration adapters and app-owned integrations stay in the app target; engine-specific primitives stay in their engine packages.

### MusicFeature package

Put the reusable Player UI and player-facing contracts here.

Recommended new folder:

- `MusicFeature/Sources/MusicFeature/Presentation/Player/`

Recommended files:

- `AuraPlayPlayerView.swift`
- `AuraPlayPlayerPresentation.swift`
- `AuraPlayPlayerCommanding.swift`
- `AuraPlayPlayerCapabilities.swift`
- `AuraPlayPlayerQueuePresentation.swift`
- `AuraPlayPlayerRoute.swift`
- `AuraPlayPlayerContentKind.swift`
- `AuraPlayPlayerScrubberView.swift`
- `AuraPlayPlayerTimeFormatter.swift`
- `AuraPlayUpNextSheet.swift`
- `AuraPlayAudioControlsSheet.swift`
- `AuraPlayVideoControlsOverlay.swift`
- `AuraPlayPlayerGestureLayer.swift`
- `AuraPlayPlayerContextMenuBuilder.swift`
- `AuraPlayShareSheetPresentation.swift`

`MusicFeature` should own:

- Player SwiftUI composition.
- Presentation structs and command protocols.
- Fake player adapters for previews and package tests.
- Scrubber UI and time-label preference keys.
- Up Next UI that targets queue-entry presentation ids.
- Audio controls UI shells that call abstract commands.
- Video controls UI shells that call abstract commands.
- Context menu shape and share/explorer presentation intents.

`MusicFeature` should not own:

- The concrete `PlaybackOrchestrator`.
- Direct SwiftData account/wallet lookups from the app target.
- Real PiP controller lifetime.
- Real `AVPlayer` construction or media loading.
- Chain-provider explorer URL policy if the app already owns the chain registry.

### Auralis app target

Put concrete adapters and app wiring here. This preserves the current architecture where Phase 8 orchestration is app-private.

Recommended new folder:

- `Auralis/Auralis/MusicApp/AuraPlay/Player/`

Recommended files:

- `AuraPlayPlayerAdapter.swift`
- `AuraPlayPlayerCommandAdapter.swift`
- `AuraPlayPlayerQueueAdapter.swift`
- `AuraPlayPlayerAudioControlsAdapter.swift`
- `AuraPlayPlayerVideoControlsAdapter.swift`
- `AuraPlayExplorerURLBuilder.swift`
- `AuraPlaySafariPresenter.swift`
- `AuraPlayPlayerSharePresenter.swift`

The app target should own:

- Mapping `PlaybackOrchestrator.state` into `AuraPlayPlayerPresentation`.
- Mapping `AuraPlayPlaybackQueue` into queue presentation rows while preserving `QueueEntry.id`.
- Calling `PlaybackOrchestrator.togglePlayPause()`, `skipToNext()`, `skipToPrevious()`, and `seek(to:)`.
- Calling queue mutation methods on the app-private queue/orchestrator boundary.
- Bridging audio tuning commands to `AuraPlayPlaybackRuntime` or the concrete audio controllers.
- Bridging video commands to `PlayerContainerView`, `PictureInPictureController`, subtitles, route picker, speed, and video gravity.
- Supplying wallet/media metadata that is not part of the package contract.
- Presenting `SFSafariViewController` and `UIActivityViewController` if those remain app-owned.

The app target should not duplicate player UI already expressed in `MusicFeature`. It should compose package views with live dependencies.

### AuraPlayVideoEngine package

Keep video-engine primitives here.

Keep or add here:

- `PlayerContainerView`
- `PictureInPictureController`
- `VideoRoutePickerView`
- `SubtitleTrackManager`
- `PlaybackSpeedController`
- video seek tolerance types
- video gravity/controller helpers that directly manipulate `AVPlayerLayer` or `AVPlayer`

Do not put full player SwiftUI chrome here. This package should stay engine-focused.

### AuraPlayAudioEngine package

Keep audio-engine primitives here.

Keep or add here:

- EQ controller/preset implementation.
- Dynamics/normalization implementation.
- AutoMix/crossfade controller implementation.
- Audio seek implementation hooks that the app adapter can call.

Do not put full player SwiftUI chrome here. This package should stay engine-focused.

### Shared seek coalescing package choice

Preferred placement: `AuraPlayMediaCore` if the type can remain engine-agnostic.

Recommended file:

- `AuraPlayMediaCore/Sources/AuraPlayMediaCore/SeekCoalescer.swift`

Use this placement if `SeekCoalescer` only knows about seconds, tolerance values, and an async seek closure.

Fallback placement: `AuraPlayVideoEngine` only if the implementation must depend on video seek tolerance or `AVPlayer`-specific APIs. If that happens, wrap it behind a `MusicFeature` command protocol so audio UI still calls the same player command path.

Avoid placing `SeekCoalescer` in the app target. The coalescing behavior is a reusable playback mechanic and needs package-level tests.

### AuraUI package

Put shared design-system and test identifiers here.

Update:

- `AuraUI/Sources/AuraUI/A11yID.swift`

Use `AuraUI` for:

- Player accessibility identifiers.
- Shared Aura/Liquid Glass primitives if Phase 10 needs new reusable player chrome.
- Existing motion policy and Reduce Motion helpers.

Do not put player-specific business state in `AuraUI`.

### Tests

Use package tests for reusable contracts and view behavior, app tests for live adapter integration.

Recommended `MusicFeature` tests:

- `MusicFeature/Tests/MusicFeatureTests/PlayerViewTests.swift`
- `MusicFeature/Tests/MusicFeatureTests/PlayerScrubberTests.swift`
- `MusicFeature/Tests/MusicFeatureTests/UpNextSheetTests.swift`
- `MusicFeature/Tests/MusicFeatureTests/PlayerControlsVisibilityTests.swift`
- `MusicFeature/Tests/MusicFeatureTests/PlayerAccessibilityTests.swift`

Recommended app tests:

- `AuralisTests/AuraPlayPlayerAdapterTests.swift`
- `AuralisTests/AuraPlayPlayerQueueAdapterTests.swift`
- `AuralisTests/AuraPlayExplorerURLBuilderTests.swift`
- `AuralisUITests/AuraPlayPlayerUITests.swift` only for flows that require app presentation or system sheets.

Keep mock-engine snapshot and interaction tests in package tests where possible. Use app tests only when the concrete orchestrator, app router, Safari presenter, share presenter, or platform sheet integration is the behavior under test.

## Required Foundations

### 1. Player presentation contract

Add a Phase 10-specific presentation boundary rather than forcing the existing `AuraPlayPlaybackPresenting` protocol to carry every video concern.

Recommended package types in `MusicFeature/Sources/MusicFeature/Presentation/Player/`:

- `AuraPlayPlayerView.swift`
- `AuraPlayPlayerPresentation.swift`
- `AuraPlayPlayerCommanding.swift`
- `AuraPlayPlayerQueuePresentation.swift`
- `AuraPlayPlayerCapabilities.swift`
- `AuraPlayPlayerContextMenuBuilder.swift`

Recommended live app adapters in `Auralis/Auralis/MusicApp/AuraPlay/Player/`:

- `AuraPlayPlayerAdapter.swift`
- `AuraPlayPlayerCommandAdapter.swift`
- `AuraPlayPlayerQueueAdapter.swift`
- `AuraPlayPlayerAudioControlsAdapter.swift`
- `AuraPlayPlayerVideoControlsAdapter.swift`

The app target should provide the concrete adapter from `PlaybackOrchestrator`, audio engine/runtime controls, video engine/runtime controls, and wallet/media metadata into the public `MusicFeature` presentation boundary. `MusicFeature` should not import app-private orchestration files.

The presentation should expose:

- Current item presentation: id, title, creator, collection, artwork, media kind, chain, contract, token id.
- Playback state: idle, loading, playing, paused, buffering, failed.
- Engine kind: audio, video, or none.
- Position: current seconds, duration seconds, buffering flag.
- Queue snapshot: current entry, upcoming entries, history entries, current entry id.
- Modes: repeat and shuffle.
- Audio capabilities: EQ presets, custom bands, crossfade, normalization.
- Video capabilities: `AVPlayer`, PiP state, subtitles, audio descriptions, speed, orientation/aspect eligibility, route picker availability.
- Sharing/explorer capabilities.

The command surface should expose:

- Toggle play/pause.
- Skip next/previous.
- Seek.
- Reorder/remove queue entry by `QueueEntry.id`.
- Set repeat/shuffle.
- Apply EQ preset and custom band gain.
- Set normalization and crossfade.
- Start/stop/restore PiP.
- Select subtitle/audio-description track.
- Set video speed.
- Set video gravity for the active item.
- Open explorer and copy contract address.

### 2. Shared SeekCoalescer

Create a shared coalescer that both the scrubber and gesture layer call. It should wrap or replace the existing video `ChaseTimeSeekCoordinator` pattern rather than creating a second implementation for audio.

Recommended shape in `AuraPlayMediaCore/Sources/AuraPlayMediaCore/SeekCoalescer.swift`:

- `public actor SeekCoalescer`
- `public func requestSeek(to:tolerance:perform:)`
- Stores only the latest target while a seek is in flight.
- Can be tested with a deterministic async seek closure.
- Does not import SwiftUI, AVFoundation, or app target types.

If tolerance cannot be made engine-neutral, keep the existing video tolerance type in `AuraPlayVideoEngine` and introduce a small engine-neutral tolerance value in `AuraPlayMediaCore` that adapters translate at the edge.

Integration rule: the UI should optimistically update during drag, then ask the coalescer to chase the final/latest requested target. Double-tap seek should call the same coalescer with `currentPosition +/- 10`.

### 3. Player-specific accessibility identifiers

Register Phase 10 identifiers in `AuraUI/Sources/AuraUI/A11yID.swift` before writing tests. Use lowercased dot-namespaced ids consistent with existing project convention.

Recommended ids:

- `player.sheet`
- `player.dismiss`
- `player.artwork`
- `player.videoSurface`
- `player.playPause`
- `player.previous`
- `player.next`
- `player.scrubber`
- `player.elapsedTime`
- `player.trailingTime`
- `player.upNext`
- `player.audioControls`
- `player.videoControls`
- `player.pip`
- `player.airplay`
- `player.subtitles`
- `player.speed`
- `player.share`
- `player.viewOnExplorer`
- `player.copyContract`
- `player.skipBack10`
- `player.skipForward10`

## Implementation Sequence

### Slice 1 - Presentation adapter and mocks

Build the presentation and command protocols first. Add mock/fake implementations for previews and tests before building the UI.

Work items:

1. Add player presentation structs in `MusicFeature/Sources/MusicFeature/Presentation/Player/`.
2. Add `AuraPlayPlayerCommanding` with async command methods in `MusicFeature`.
3. Add fake player presenters/commanders in `MusicFeature/Tests/MusicFeatureTests/` for package view tests.
4. Add app-target adapters in `Auralis/Auralis/MusicApp/AuraPlay/Player/` from `PlaybackOrchestrator` to the new presentation model.
5. Map `OrchestratorState` into presentation state inside the app adapter.
6. Map `AuraPlayPlaybackQueue` into queue presentation entries inside the app adapter, preserving `QueueEntry.id`.
7. Keep `PlaybackOrchestrator`, `EngineArbiter`, and concrete engine controller lifetimes app-private for this phase.

Exit criteria:

- A preview can render audio and video player states without real engines.
- The adapter exposes current item, engine kind, position, queue, repeat/shuffle, and content-specific capabilities.
- No SwiftUI player view directly imports app-private orchestration types unless it lives in the app target by design.

### Slice 2 - Full-screen player shell (P10-001)

Introduce `AuraPlayPlayerView` as the full player sheet presented from the Phase 9 mini-player.

Work items:

1. Present from `AuraPlayMiniPlayerView` using the Phase 9 matched geometry identity.
2. Audio branch: large artwork, ambient background, content text, transport.
3. Video branch: full-bleed `PlayerContainerView`, shared player layer callback, content text/chrome overlay.
4. Add dismiss chevron and swipe-down dismissal that does not call pause/stop.
5. Add title marquee only when Reduce Motion is disabled; use truncation when enabled.
6. Apply Liquid Glass to custom chrome using grouped `GlassEffectContainer`/`glassEffect` where available, with fallbacks for older OS targets if needed.

Exit criteria:

- Audio shows artwork and ambient treatment.
- Video shows the live `PlayerContainerView` path.
- Transport buttons call commands only.
- Dismiss leaves orchestrator state unchanged.
- Player view has no local play/pause boolean.

### Slice 3 - Scrubber and time labels (P10-002)

Replace direct slider seek behavior with a dedicated scrubber component.

Work items:

1. Add `SeekCoalescer` and unit tests.
2. Add `PlayerScrubberView` with drag state scoped to display only.
3. Read position from presentation state, not a local timer.
4. Optimistically display drag position during drag.
5. Coalesce seek on drag end and any rapid target changes.
6. Add right-side time label toggle between remaining and total duration.
7. Persist the label preference with `@AppStorage`.
8. Show buffering as a subtle track pulse.

Exit criteria:

- A fast drag does not call seek per touch movement.
- Audio and video both seek through `SeekCoalescer`.
- Time label preference survives relaunch.
- Buffering state is visible without introducing a separate spinner.

### Slice 4 - Up Next queue UI (P10-003)

Build `UpNextSheet` from the presentation queue snapshot.

Work items:

1. Show the current entry as a non-removable Now Playing row.
2. Show upcoming entries in a reorderable list.
3. Call reorder with `QueueEntry.id` and destination index.
4. Call remove with `QueueEntry.id` only for upcoming entries.
5. Show history in a collapsed, read-only Recently Played section.
6. Surface repeat and shuffle toggles backed by the same storage/state used in main transport.
7. Reuse Phase 9 library item cell presentation where possible.

Exit criteria:

- Duplicate media items in the queue remain independently actionable.
- Now Playing has no swipe-to-remove action.
- History taps do not start playback.
- Repeat/shuffle changes are reflected everywhere within one render pass.

### Slice 5 - Audio controls (P10-004)

Build `AudioControlsSheet` and only expose it when the active engine/content is audio.

Work items:

1. Add audio controls button only for audio presentation states.
2. EQ preset segmented control maps to the existing preset cases.
3. Custom EQ exposes the 10 bands matching the engine band order.
4. Band changes write through the command adapter immediately.
5. AutoMix slider binds to the same crossfade storage value used by the controller.
6. Normalization toggle writes through the existing setting path.
7. Caption honestly describes the normalization target as an approximation.

Exit criteria:

- Audio controls entry point is absent for video.
- EQ changes update the engine/controller state.
- Crossfade changes affect the next transition through existing storage.
- Custom gains restore on relaunch.

### Slice 6 - Video controls (P10-005)

Move video-specific chrome from the wireframe into production player components.

Work items:

1. Add `VideoControlOverlay` over the video branch only.
2. Auto-hide controls after inactivity; tap middle zone reveals/hides.
3. PiP button uses the `AVPlayerLayer` from `PlayerContainerView`.
4. AirPlay hosts `VideoRoutePickerView`.
5. Subtitle menu is absent when there are no legible or audio-description tracks.
6. Speed selector uses `PlaybackSpeedOption` and `PlaybackSpeedController` state.
7. Landscape/fullscreen button is present only when video presentation info permits it.
8. Add contrast scrim behind text and controls.

Exit criteria:

- Entire video control bar is absent for audio.
- PiP uses the shared layer, with no second video rendering path.
- Subtitle menu absence is structural, not an empty menu.
- Speed selection persists and reflects current state.

### Slice 7 - Gesture layer (P10-006)

Add direct manipulation gestures after scrubber and video controls exist, so gesture priority can be tested against real controls.

Work items:

1. Left third double-tap calls seek current position minus 10 seconds through `SeekCoalescer`.
2. Right third double-tap calls seek current position plus 10 seconds through `SeekCoalescer`.
3. Middle third single tap toggles video controls and never seeks.
4. Pinch toggles video gravity between `.resizeAspect` and `.resizeAspectFill` for video only.
5. Reset video gravity when the active video item changes.
6. Swipe-down dismisses beyond threshold and springs/fades back below threshold.
7. Use fade feedback when Reduce Motion is enabled.

Exit criteria:

- Rapid double-tap sequences coalesce instead of stacking seeks.
- Scrubber gestures do not trigger player dismissal.
- Pinch zoom does not persist across video items.
- Gesture feedback remains accessible with Reduce Motion.

### Slice 8 - Sharing and on-chain context menu (P10-007)

Build one context menu builder and use it from both player and library cells.

Work items:

1. Add `AuraPlayShareSheet` using `UIActivityViewController` behind a SwiftUI wrapper.
2. Share title/creator text and artwork image when available.
3. Add `ExplorerURLBuilder` driven by ChainRegistry and media token metadata.
4. Open explorer URLs through `SFSafariViewController`.
5. Copy raw contract address and show toast confirmation.
6. Reuse the same context menu builder from Phase 9 library cells.

Exit criteria:

- Explorer URLs are tested for all supported chains.
- Explorer opens in app, not via full app switch.
- Share content is correct for seeded media.
- No duplicate context menu construction exists.

### Slice 9 - Accessibility hardening (P10-008)

Do the accessibility pass before snapshots are finalized, not after tests are already brittle.

Work items:

1. Every control has a concise accessibility label and expected trait.
2. Scrubber implements `accessibilityAdjustableAction` and announces elapsed/total time.
3. VoiceOver-only skip back/forward 10 second buttons exist for gesture zones.
4. Icon controls maintain at least 44 point targets.
5. Dynamic Type at XXXL does not overlap scrubber, text, or control bars.
6. Matched transitions, gesture feedback, and auto-hide animations respect Reduce Motion.
7. Video text uses scrim/gradient for WCAG AA contrast.
8. Artwork, title, creator, and collection are grouped where that creates a better VoiceOver reading order.

Exit criteria:

- Accessibility Inspector reports no missing-label warnings across player UI.
- VoiceOver users can operate all gesture-only behaviors through accessible controls.
- XXXL text does not break layout.
- Bright video fixture keeps text readable.

### Slice 10 - Integration and snapshot tests (P10-009)

Add tests after the presentation adapter and controls are stable.

Work items:

1. Snapshot audio player in light/dark and standard/XXLarge Dynamic Type.
2. Snapshot video player with control bar visible in light/dark and standard/XXLarge Dynamic Type.
3. Snapshot audio player with EQ sheet open.
4. Interaction test scrubber coalesced seeks.
5. Interaction test double-tap seek zones and middle-zone toggle.
6. Interaction test Up Next reorder/remove by `QueueEntry.id`.
7. Test audio-to-video content switch hides/shows correct control families.
8. Test scrubber drag does not trigger swipe-down dismiss.
9. Keep test doubles in memory and avoid real engine startup.

Exit criteria:

- Full Phase 10 suite completes in under 10 seconds.
- Snapshots are stable across five consecutive CI runs.
- No test relies on live network, real AV playback, or real PiP availability.

## Ticket Mapping

| Ticket | Primary implementation slice | Key files/components |
| --- | --- | --- |
| P10-001 | Slice 2 | `AuraPlayPlayerView`, mini-player presentation, audio/video branches, transport |
| P10-002 | Slice 3 | `SeekCoalescer`, `PlayerScrubberView`, time labels |
| P10-003 | Slice 4 | `UpNextSheet`, queue entry rows, repeat/shuffle controls |
| P10-004 | Slice 5 | `AudioControlsSheet`, EQ/custom bands, AutoMix, normalization |
| P10-005 | Slice 6 | `VideoControlOverlay`, PiP, AirPlay, subtitles, speed, orientation |
| P10-006 | Slice 7 | `PlayerGestureLayer`, double-tap seek, pinch zoom, swipe dismiss |
| P10-007 | Slice 8 | `AuraPlayShareSheet`, `ExplorerURLBuilder`, context menu builder |
| P10-008 | Slice 9 | Accessibility labels, adjustable scrubber, VO controls, Dynamic Type, contrast |
| P10-009 | Slice 10 | Snapshot tests, interaction tests, fake player/orchestrator adapters |

## Design System Direction

Use the established Auralis/Aura visual pattern from the post-login home, gateway, gas, and existing AuraPlay surfaces:

- Dense, useful controls rather than a landing-page style layout.
- Artwork/video as the first visual signal.
- Liquid Glass chrome for clustered controls, not as decoration everywhere.
- System symbols for transport, PiP, AirPlay, subtitles, queue, share, and context actions.
- Scrims over video where content unpredictability affects contrast.
- Semantic fonts and scalable layout constraints.
- Stable control dimensions so state changes do not resize the player.

Liquid Glass implementation notes from current SwiftUI docs:

- Use `glassEffect(_:in:)` for custom glass views.
- Use `GlassEffectContainer` to group multiple glass shapes for performance and morphing.
- Use `glassEffectID(_:in:)` for glass effect identity during transitions where appropriate.
- Prefer system toolbar/button glass styles where standard controls already supply them.
- Avoid too many independent glass effects onscreen at once.

## Risks And Mitigations

### Risk: The existing audio protocol becomes a dumping ground

Mitigation: create a Phase 10 player-specific presentation/command boundary. Keep `AuraPlayPlaybackPresenting` available for existing surfaces until migration is complete.

### Risk: Video wireframe logic stays duplicated

Mitigation: extract production-ready video controls from the wireframe into reusable components, then leave the wireframe as a QA/dev harness or retire it in a later cleanup.

### Risk: Scrubber and gestures diverge

Mitigation: implement `SeekCoalescer` before either UI path ships, and test both paths against the same fake seek operation.

### Risk: Queue duplicate-item behavior regresses

Mitigation: every queue UI command carries `QueueEntry.id`. Add a duplicated-media fixture to the Up Next tests.

### Risk: Full player accidentally controls playback lifetime

Mitigation: tests assert dismiss does not call pause/stop and does not alter `OrchestratorState`.

### Risk: Video contrast fails on bright content

Mitigation: build scrim/gradient into video chrome by default, then snapshot against a bright fixture.

### Risk: Real engine dependencies slow tests

Mitigation: test the player view with fake presentation and command adapters. Reserve real engine verification for engine-level suites and focused integration tests.

## Done Definition

Phase 10 is complete when:

1. The Phase 9 mini-player presents the full player.
2. Audio and video content render through distinct branches backed by one current orchestrator item.
3. Transport, scrubber, queue, audio controls, video controls, gestures, and sharing all command existing orchestrator/engine services.
4. No playback state is duplicated inside player SwiftUI views.
5. Audio-only and video-only controls are absent for the wrong content type.
6. PiP uses the shared `PlayerContainerView` layer.
7. Accessibility audit passes for VoiceOver, Dynamic Type, Reduce Motion, and text contrast.
8. Phase 10 snapshots and interaction tests pass for audio and video content types.
9. The full Phase 10 test suite runs under 10 seconds with mock engines/adapters.
