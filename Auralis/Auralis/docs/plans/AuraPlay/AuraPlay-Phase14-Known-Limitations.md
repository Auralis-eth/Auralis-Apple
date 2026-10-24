# AuraPlay Phase 14 - Known Limitations

Updated: 2026-10-22

These are known v1 limitations or release notes. They should not be rediscovered as ship-blocking bugs unless product scope changes.

| Area | Limitation | Status |
| --- | --- | --- |
| WebM | WebM remains unsupported in the current video validation path. | Known v1 limitation |
| Cross-device sync | Playlists, playback state, cache state, and Smart Resume data are local-device features. | Known v1 limitation |
| Loudness | Normalization is controlled through current audio settings; true LUFS analysis remains future work unless separately implemented. | Known v1 limitation |
| Ambisonic / advanced spatial audio | Current video engine handles current 2D/stereo/spatial presentation policy, not full ambisonic authoring. | Known v1 limitation |
| Snapshot fidelity | Library/player snapshots render on macOS host, not iOS device pixels. | Accepted test limitation |
| Physical-device performance | Battery, AirPlay, interruptions, and route-change behavior still require final hardware sign-off. | Release gate |
| Third-party wallet support proof | Rabby, Rainbow, Coinbase Wallet, MetaMask, Phantom, Backpack, Solflare, Privy, and Dynamic must each pass physical-device route QA before support is claimed. | Release gate |
| App Store final archive | Privacy manifest and permission strings are test-covered but still need archive/upload review against Apple's current warnings. | Release gate |
| AuraPlay schema evolution | Pre-release migration scaffolding was removed. AuraPlay currently ships a flat `AuraPlaySchema`; any future persisted-schema change requires an explicit migration plan and upgrade fixtures before release. | Intentional current baseline |
| Inventory fallback | AuraPlay inventory is sourced by wallet/chain NFT discovery. It does not silently mirror the primary NFT store when discovery is unavailable. | Intentional architecture constraint |
| Auto-organization apply | The production UI provides a receipt-backed preview only. It does not mutate playlists. | Intentional safety constraint |
| Legacy primary playlist model | The app-level `Playlist` helpers remain for compatibility and existing non-AuraPlay consumers/tests. They are not the shipping Music-tab playlist store and are not synchronized with AuraPlay playlists. | Explicit compatibility boundary |
