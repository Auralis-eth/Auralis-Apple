# ADR-006: AuraPlay Unified Position Persistence

## Status

Accepted.

## Context

AuraPlay audio and video grew separate position persistence paths. Audio persistence was expected to land in playback orchestration, while video had a wireframe-local `UserDefaults` store. That split makes resume behavior drift and leaves cold-launch restore without one owner.

## Decision

Playback position is owned by the Phase 8 playback orchestration layer. The orchestrator writes audio and video position through one `PositionPersistenceCoordinator`, backed by the AuraPlay SwiftData `AuraPlayPlaybackPositionState` model and model actor.

The coordinator writes the active engine's current time on cadence and on lifecycle boundaries: pause, stop, background transition, track change, and completion. Completion resets the stored position to zero and records completion metadata so finished items resume from the beginning.

Cold launch restores only the most recent valid playable item into a paused single-entry queue with origin `.restored`. The full queue is intentionally not persisted.

## Consequences

- There is one live writer for playback position across audio and video.
- Video no longer owns an independent `UserDefaults` write path for production playback state.
- Resume thresholds are shared: positions near the start or final seconds are not offered as resume points.
- Queue reconstruction is deliberately minimal until a later phase introduces durable queue persistence.
