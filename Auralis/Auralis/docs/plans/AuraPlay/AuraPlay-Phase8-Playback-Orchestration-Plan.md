# AuraPlay Phase 8 Playback Orchestration Plan

## Summary

Implement playback orchestration in the app target with `PlaybackOrchestrator` as the target source of truth. This app has no released compatibility contract, so Phase 8 should not preserve parallel playback authorities as a migration strategy. Existing runtime code may remain temporarily as an adapter, but new playback behavior should route through the orchestrator and its collaborators.

The ship invariant is strict: audio and video are never active simultaneously, and stale async loads cannot overwrite newer playback requests.

## Implementation Sequence

1. Add runtime queue/state foundations: `QueueEntry`, `PlaybackQueue`, `QueueOrigin`, repeat/shuffle support, and duplicate-item-safe queue operations.
2. Add `PlaybackOrchestrator` as an `@MainActor @Observable` state machine with `OrchestratorState`, `playbackGeneration`, active engine tracking, current position, and public controls.
3. Split runtime collaborators out of the current large class: `EngineArbiter`, `RemoteCommandCoordinator`, `QueueAdvanceCoordinator`, `ErrorRecoveryCoordinator`, and `PositionPersistenceCoordinator`.
4. Add durable playback position support with `AuraPlayPlaybackPositionState`, a SwiftData model actor, completion reset, most-recent fetch, and cold-launch restore lookup.
5. Integrate audio and video through orchestrator-facing protocols, remove the video-local live writer, and keep resume thresholds at after 5 seconds and before final 5 seconds.
6. Cut production audio, video, remote command, queue advance, and position persistence flows over to the orchestrator instead of keeping duplicated runtime-owned behavior.
7. Document the architecture in ADR-006 and update AuraPlay status, gaps, and `Journal.md`.

## Test Plan

Use Swift Testing in `AuralisTests`, with no real `AVAudioEngine` or `AVPlayer`.

Required scenarios:

- duplicate `QueueEntry` identity works for remove/reorder/current tracking
- audio-to-video handoff awaits audio stop before video load
- rapid `play(A)` then `play(B)` discards stale A load
- superseded ready callback does not transition state
- remote command mapping covers all command cases
- skip-forward uses audio seek or video smooth seek based on active engine
- remote command subscription remains single across handoffs
- audio `.playing` triggers prefetch then gapless prepare for next cached item
- video end advances or idles when exhausted
- repeat one, repeat all, shuffle, and duplicate media traversal
- 3 consecutive failures trip circuit breaker
- position persistence writes on cadence and pause/stop for audio and video through one coordinator
- cold launch restores valid recent item paused with `.restored` origin and no autoplay

Current focused suite: `AuraPlayPhase8PlaybackOrchestrationTests` covers 19 scenarios and passed locally on 2026-07-11.

## Defaults

- Phase 8 stays app-target scoped.
- Full queue persistence remains out of scope.
- `AuraPlayPlaybackPositionState` is added because no existing SwiftData playback state model was present.
- Video's current wireframe remains the Phase 8 video surface.
- `MusicFeature` remains a presentation/service contract package, not the owner of concrete engine orchestration.
- `AuraPlayPlaybackRuntime` is a temporary adapter/cutover surface, not the long-term playback authority.
