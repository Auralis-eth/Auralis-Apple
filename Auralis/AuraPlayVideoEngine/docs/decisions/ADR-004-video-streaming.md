# ADR-004: Video Streaming, Progressive Cache, And Offline Reuse

## Status
Accepted for Phase 7, updated after progressive/offline playback work.

## Decision
AuraPlay video playback receives already-resolved HTTPS URLs from the host app.

For HLS URLs, the engine keeps normal `AVPlayer` streaming behavior and offers `HLSVideoOfflineDownloadManager` for offline `.movpkg` package downloads through `AVAssetDownloadURLSession`.

For progressive HTTPS media such as MP4 or MOV, the engine can either stream directly with `AVPlayer` or opt into `ProgressiveVideoCachingPipeline`. The pipeline rewrites the playback URL to the package's custom asset scheme, services AVFoundation byte-range requests through `AVAssetResourceLoaderDelegate`, writes received ranges into a sparse disk cache, and marks the file available when the cached ranges become complete.

`VideoOfflineManifestStore` records downloadable media state so `VideoAssetLoader` can prefer local files when a source URL has an available offline record.

The video engine still does not accept raw `ipfs://` or `ar://` URLs. Host app adapters are responsible for gateway resolution before calling `VideoPlayerController.load(resolvedURL:)`.

## Rationale
`AVPlayer` already handles regular progressive HTTP playback, HLS, buffering, and byte-range requests for supported servers. That remains the default path.

Offline reuse and play-while-downloading need explicit ownership because AVPlayer does not provide a general disk cache for progressive HTTP assets. The custom resource-loader path gives AuraPlay a controlled cache bridge without forcing every playback to become a download.

Keeping gateway resolution outside this package preserves a standalone engine boundary while still allowing AuraPlay to reuse its existing gateway fallback chain through `VideoGatewayResolving`.

## Consequences
- MP4/MOV/HLS are the intended v1 formats.
- WebM is rejected defensively as unsupported.
- Progressive cache support is opt-in through `ProgressiveVideoCachingPipeline`.
- HLS offline support uses the system asset-download package flow rather than raw `URLSession` bytes.
- Gateway stall fallback is expressed through protocols so the app can swap in its real resolver later.
- Editing timelines, effects, and export remain outside this playback package.
- Live Apple Immersive Video production tooling is a separate boundary: SMPTE 2110 ingest/playout, streamed ProRes frames, ASAF PCM channel beds/objects, per-frame JSON metadata, MOV writing, MEBX metadata tracks, and `kVTProjectionKind_AppleImmersiveVideo`/`vexu` signaling should not be folded into this playback engine.
