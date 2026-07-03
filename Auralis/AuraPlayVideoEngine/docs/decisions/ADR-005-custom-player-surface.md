# ADR-005: One Custom AVPlayerLayer Surface

## Status
Accepted for Phase 7.

## Decision
AuraPlayVideoEngine uses one custom `AVPlayerLayer`-backed surface, exposed as `PlayerContainerView`.

SwiftUI `VideoPlayer` is not used by this package.

## Rationale
The custom layer is required for:

- Picture in Picture setup with a player layer on iOS
- custom AuraPlay controls
- future double-tap seek and pinch-to-zoom gestures
- subtitle and overlay positioning
- a single surface contract shared by the app and demo

## Consequences
- iOS uses a `UIViewRepresentable` whose backing layer is `AVPlayerLayer`.
- macOS uses an `NSViewRepresentable` with a hosted `AVPlayerLayer`.
- PiP is implemented for iOS custom-layer playback. The macOS package API currently returns unsupported rather than switching to `AVPlayerView`, which would violate the single-surface decision.
