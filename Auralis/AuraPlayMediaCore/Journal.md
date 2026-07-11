# AuraPlayMediaCore Journal

## The Big Picture

`AuraPlayMediaCore` is the shared vocabulary table for AuraPlay media packages. Audio and video can still run their own kitchens, but they no longer need two labels for the same ingredients: playable media identity, cache state, cache progress, shared playback ticks, and common media errors live here.

## Architecture Deep Dive

Think of this package like the prep counter between two stations. `AuraPlayAudioEngine` owns audio decoding, graph control, loudness, gapless scheduling, and playback details. `AuraPlayVideoEngine` owns AVPlayer control, picture-in-picture, video tracks, multiview, and presentation rules. `AuraPlayMediaCore` owns only the neutral contracts both stations can touch without dragging in the other station's equipment.

That keeps the dependency direction clean:

- app/features can depend on media contracts when they only need to describe media
- audio/video engines depend on media contracts when they implement behavior
- media core does not depend on either engine

## The Codebase Map

- `Package.swift` defines the Swift package and its single library product.
- `Sources/AuraPlayMediaCore/AuraPlayableMedia.swift` holds media identity, content kind, cache state, and type erasure.
- `Sources/AuraPlayMediaCore/AuraPlayError.swift` holds the shared base media error.
- `Sources/AuraPlayMediaCore/MediaCacheContracts.swift` holds cache progress, loudness measurement, cache manager protocol, and cache key normalization.
- `Sources/AuraPlayMediaCore/PlaybackTick.swift` holds shared playback progress.
- `Tests/AuraPlayMediaCoreTests/` holds focused contract tests.

## Tech Stack & Why

Swift Package Manager is enough here because the package is a small library with no app bundle, no UI, and no resources. Swift 6 keeps concurrency contracts honest, and Swift Testing gives the package modern, low-boilerplate contract tests when run under the full Xcode toolchain.

The platform floor mirrors the engine packages: iOS 26, macOS 26, and visionOS 26. That lets audio and video import the core package without a platform mismatch.

## The Journey

2026-07-07: The first slice moved the generic media contracts out of `AuraPlayAudioEngine` and the shared `PlaybackTick` shape out of `AuraPlayVideoEngine`. The old engine modules keep source-compatible typealiases and re-exports, so existing imports still work while the canonical definitions live here.

Validation had a small plot twist. The library builds under the current CommandLineTools shell, but Swift Testing and SwiftUI macro plugins are not available there. Package tests and demo executable builds need the full Xcode toolchain. While proving the video package with the new dependency, two macOS availability traps surfaced in `AuraPlayVideoEngine`; those stayed in the video package where they belong.

## Engineer's Wisdom

Shared packages should be a spice rack, not a junk drawer. If a type needs AVAudioEngine, AVPlayer, SwiftUI, UIKit, AppKit, cache file IO policy, or presentation behavior, it probably does not belong here yet. Move only the contracts that are genuinely shared and stable enough to earn a neutral home.

The first migration should preserve source compatibility when possible. Typealiases and re-exports are boring, which is exactly why they are useful during package-boundary work.

## If I Were Starting Over...

I would create the media core before the audio and video engines grew independent vocabularies. That would have made the first extraction smaller and avoided the question of which package's names should become canonical. The useful rule for next time: when two sibling packages both start saying "media," create the dictionary before each one writes its own dialect.
