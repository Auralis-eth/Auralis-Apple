# ADR-003: Audio Is Download-Then-Play

## Status

Accepted for Phase 6 v1.

## Context

AuraPlay needs gapless playback, EQ, dynamics processing, loudness normalization, and recovery from route changes and interruptions. The v1 signal path is built on `AVAudioEngine` and buffer scheduling.

`AVAudioFile` and player-node buffer scheduling require readable local media. A remote URL that is still only a network stream is not a stable AVAudioEngine source. Building a real streaming decoder path inside this phase would also complicate gapless transitions, effects, recovery, and offline support.

## Decision

AuraPlay audio is downloaded to a local cache before the AVAudioEngine graph plays it.

The cache manager may expose a progressive local-file readiness API so playback can start once enough bytes are available and the file can be opened safely. That is still a local-file contract, not remote streaming through AVAudioEngine.

## Consequences

- Gapless scheduling and effects operate on local files.
- Offline playback and LRU eviction become first-class engine concerns.
- Media cache progress is part of the playback contract.
- HLS or other true streaming audio uses a separate system-player route; see ADR-004 for the AirPlay-optimized `AVQueuePlayer` path.
- Ogg/Opus/native-streaming codecs remain backlog work through decoder plugins.

## Non-Goals

- No HLS path in Phase 6.
- No remote stream rendered directly through AVAudioEngine.
- No ambisonic/spatial graph in the v1 default path.
