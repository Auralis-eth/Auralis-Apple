# AuraPlay Phase 14 - Known Limitations

Updated: 2026-07-26

These are known v1 limitations or release notes. They should not be rediscovered as ship-blocking bugs unless product scope changes.

| Area | Limitation | Status |
| --- | --- | --- |
| WebM | WebM remains unsupported in the current video validation path. | Known v1 limitation |
| Cross-device sync | Playlists, playback state, cache state, and Smart Resume data are local-device features. | Known v1 limitation |
| Loudness | Normalization is controlled through current audio settings; true LUFS analysis remains future work unless separately implemented. | Known v1 limitation |
| Ambisonic / advanced spatial audio | Current video engine handles current 2D/stereo/spatial presentation policy, not full ambisonic authoring. | Known v1 limitation |
| Snapshot fidelity | Library/player snapshots render on macOS host, not iOS device pixels. | Accepted test limitation |
| Physical-device performance | Battery, AirPlay, interruptions, and route-change behavior still require final hardware sign-off. | Release gate |
| App Store final archive | Privacy manifest and permission strings are test-covered but still need archive/upload review against Apple's current warnings. | Release gate |
| AuraPlay schema migration | AuraPlay now opens through `AuraPlayMigrationPlan` with V1-to-V2 lightweight migration coverage for representative media, playback state, and playlist data. | Resolved for P14-007 automated gate |
