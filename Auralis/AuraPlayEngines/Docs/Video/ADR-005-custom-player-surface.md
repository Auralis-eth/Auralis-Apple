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
- The custom layer remains the right surface for Aura controls, PiP, overlays, and normal 2D playback.
- Spatial video on the custom inline layer must be treated as a 2D/fallback presentation, not as the full Photos-style spatial experience on visionOS.
- Apple Projected Media Profile and Apple Immersive Video should route through host-app system presentation: Quick Look for managed previews, AVKit `AVPlayerViewController` plus `AVExperienceController` for system immersive transitions, or RealityKit `VideoPlayerComponent` for custom immersive scenes.
- `AVPlayerViewController` expanded/fullscreen can be modeled as a separate stereo, docked theater, or immersive portal route, but it remains a host-owned handoff and is not the same contract as `PlayerContainerView`.
- RealityKit progressive/full/mixed immersive spaces are out of scope for this `AVPlayerLayer` surface; the package may describe the policy, but the host app owns the scene and transition lifecycle.
- visionOS custom environments are host-app product surfaces. `ImmersiveSpace` scenes, Reality Composer Pro docking regions, media reflections, environment probes, passthrough tint/brightness, reverb presets, immersive environment picker registration, and `AVPlayerViewController.groupExperienceCoordinator` SharePlay environment sync should live in the host adapter or app, not this playback surface.
