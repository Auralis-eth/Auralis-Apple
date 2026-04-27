# Auralis Project Memory

## Project Overview

Auralis is a SwiftUI app that combines wallet-based NFT discovery, local NFT persistence, an Aura-branded home/dashboard experience, gas tools, and an NFT-driven music player.

The main user journey looks like this:

- enter or restore a wallet/account through the gateway flow
- fetch NFTs for that account from the network layer
- persist NFTs and related models locally with SwiftData
- explore them through the Aura home, newsfeed, gas, and music surfaces

This is not a single-purpose CRUD app. It is a stateful app shell with multiple product surfaces sharing wallet identity, persisted NFT data, and a long-lived audio engine.

## Architecture Decisions

- `AuralisApp` owns the app scene and installs the SwiftData model container for core persisted models.
- `MainAuraView` is the app shell. It decides between gateway, loading, and main-tab experiences and owns shared app-level state such as the current account, selected chain, `NFTService`, and `AudioEngine`.
- `MainTabView` is the feature router for the main app surfaces: Home, NewsFeed, Gas, Music, and placeholder tabs.
- `NFTService` is the orchestration layer above `NFTFetcher`. It refreshes NFTs, parses metadata, persists results into SwiftData, and cleans up stale records.
- `NFTFetcher` handles account validation, paginated network fetches, throttling, retry/backoff behavior, and API error handling.
- `AudioEngine` is a shared `@MainActor` playback engine built on `AVAudioEngine` and `AVAudioPlayerNode`. It handles remote loading, queue navigation, cancellation of stale loads, and playback state exposed to the music UI.
- The Aura home experience includes deterministic aurora prompt generation based on wallet and chain information. Treat that as product logic, not just decoration.
- Legacy music code still exists under `MusicApp/OLD/`. Confirm active call paths before making audio-related changes.

## Important Conventions

- SwiftUI-first, state-driven UI.
- Prefer Swift concurrency and async/await over callback-heavy APIs.
- Prefer dependency injection and explicit ownership for services that need stable lifetimes.
- Prefer instance properties, instance methods, and injected values over `static` functions or `static` vars.
- Avoid `static` unless it is clearly the right modeling choice, such as a true constant namespace or a type-level API that would be awkward or misleading as an instance member.
- Do not reach for `static` as a convenience shortcut. In this codebase it usually makes testing, composition, and evolution harder.
- Keep changes tight in scope. Some files, especially `NFT.swift`, already carry too many responsibilities.
- Preserve the existing Aura visual language unless the task explicitly asks for redesign.
- Avoid force unwraps.
- Prefer SwiftData-aware changes that respect the current model container and `ModelContext` ownership.

## Build And Run

- Open the project in Xcode and use the active `Auralis` scheme.
- Build with Xcode or the MCP `BuildProject` tool.
- Use `XcodeRefreshCodeIssuesInFile` for quick compiler diagnostics while iterating.
- Unit tests live in `AuralisTests`.
- UI tests live in `AuralisUITests`.

## Codebase Map

- `Auralis/Aura/`
  Main app UI, including auth, home, tabs, and newsfeed.
- `Auralis/DataModels/`
  Persisted models and domain types such as `NFT`, `EOAccount`, `Chain`, and related helpers.
- `Auralis/Networking/`
  NFT fetching, Alchemy integration, throttling, caching, and secret-backed configuration.
- `Auralis/MusicApp/AI/Audio Engine/`
  Active audio engine and playlist stack.
- `Auralis/MusicApp/AI/V1/`
  Music UI built on top of the shared audio engine.
- `Auralis/MusicApp/OLD/`
  Legacy code. Do not assume it is part of the current path without checking.
- `Auralis/Helpers/`
  Utility extensions and metadata helpers.

## Quirks And Gotchas

- `NFT.swift` is much larger than its name suggests and contains more than just the NFT model. Read carefully before editing.
- Wallet/account state is mirrored across `@AppStorage`, `@Query`, and `@State` in the shell. Changes there can ripple through app launch, refresh, and logout behavior.
- NFT loading is paginated and rate-limited. Regressions in retry logic or throttling can look like UI bugs even when the root cause is networking.
- Audio loading has explicit stale-task cancellation logic. Preserve that discipline when changing playback behavior.
- Some feature areas are more complete than others. A few tabs and views are scaffolds or placeholders.

## Editing Guidance

- Before changing audio code, confirm whether the active path runs through `AudioEngine` and the `MusicApp/AI/` views.
- Before changing persistence behavior, check how `MainAuraView`, `NFTService`, and SwiftData interact.
- If a helper feels like it wants to become `static`, pause and consider whether it should instead be:
  an injected dependency, an instance method on the owning type, a small value type, or a private local function.
- Favor designs that keep state and behavior close together instead of building JavaScript-style utility namespaces.