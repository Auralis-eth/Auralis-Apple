# Auralis Journal

## The Big Picture

Auralis is what happens when a crypto wallet viewer, an NFT discovery app, and an experimental music player all end up at the same late-night product jam and decide to stay together.

The app opens with a wallet-style gateway, loads NFTs for an entered account, stores them locally with SwiftData, and then fans that data out into a few different experiences:

- an Aura home screen with glassy cards and AI-generated aurora backgrounds
- a newsfeed-style NFT browser
- a gas price utility
- a music player that treats NFT metadata as a playable media library

The vibe is part portfolio, part dashboard, part creative lab. It is not a narrow single-purpose app, and that matters when reading the code: Auralis is a hub, not a one-lane tool.

## Architecture Deep Dive

Think of the app like a small venue with a strict front door, a coat check, and several rooms.

`AuralisApp` is the building lease. It creates the app scene and installs the SwiftData container for the core persisted models.

`MainAuraView` is the front desk. It decides whether the user should see:

- the gateway/login flow
- the loading state while NFT data is being refreshed
- the real tab experience once an account is available

That view also bridges long-lived app state:

- wallet identity via `@AppStorage`
- persisted accounts via `@Query`
- NFT loading via `NFTService`
- audio playback via a shared `AudioEngine`

`MainTabView` is the hallway. It routes the user into the different rooms:

- `Home`
- `NewsFeed`
- `Gas`
- `Music`
- a few placeholder tabs still waiting for their furniture

The data path is fairly clean:

1. A wallet address enters through the gateway.
2. `MainAuraView` resolves that address to an `EOAccount`.
3. `NFTService` asks `NFTFetcher` to pull pages of NFTs.
4. `NFTFetcher` talks to the network layer, handles retries/rate limiting, and returns model objects.
5. `NFTService` parses metadata, writes to SwiftData, and cleans out stale NFTs.
6. Feature views read from that local model layer rather than reinventing fetch logic.

The audio side is its own little backstage crew. `AudioEngine` is a `@MainActor` observable object wrapped around `AVAudioEngine` and `AVAudioPlayerNode`. It handles:

- loading local or remote media
- queueing previous/next NFT tracks
- interruption handling
- cancellation of stale loads
- lightweight playback state for the mini-player and music UI

The most important architectural pattern here is "stateful shell, feature rooms, shared services." The code is not purely layered in a textbook sense, but the app shell, feature views, models, and service layer are distinct enough to navigate with confidence.

## The Codebase Map

If this repo were a city map, here is where the neighborhoods are:

- `Auralis/Aura/`
  The main UI shell. Authentication/gateway flow, home dashboard, tabs, newsfeed, and shared presentation bits live here.

- `Auralis/DataModels/`
  SwiftData-backed models and domain types. `NFT`, `EOAccount`, `Chain`, gas estimate models, and related supporting structures live here.

- `Auralis/Networking/`
  The internet plumbing. This is where Alchemy access, NFT fetching, throttling, caching, and secrets wiring happen.

- `Auralis/MusicApp/AI/Audio Engine/`
  The modern music stack. `AudioEngine`, playlists, CRUD helpers, and playlist storage logic are here.

- `Auralis/MusicApp/AI/V1/`
  Music UI surfaces such as the mini-player and now-playing view.

- `Auralis/MusicApp/OLD/`
  The archaeological layer. Old audio/player code still exists, which means future refactors need to be careful about what is truly active versus merely haunting the repo.

- `Auralis/Helpers/`
  String, URL, color, and metadata utilities.

- `AuralisTests/`
  Unit tests, including good coverage around playlists, secrets, string helpers, and URL behavior.

- `AuralisUITests/`
  UI smoke-test territory.

One especially important navigation note: `NFT.swift` is not "just the NFT model." It is a large mixed-use file with model code, tag-related views, validation helpers, and utility logic. It behaves less like a single file and more like an overstuffed closet.

## Tech Stack & Why

### SwiftUI

SwiftUI is the obvious fit here because the app is state-heavy and visually opinionated. There are multiple app modes, modal surfaces, tab flows, generated backgrounds, and reactive loading states. SwiftUI keeps that manageable without forcing a UIKit coordination tax.

### SwiftData

SwiftData is doing the job of the local memory palace. NFT data, accounts, playlists, and tags need to survive view refreshes and app restarts. For a product like this, where network data becomes a browsing library, local persistence is not optional.

### AVFoundation

The audio player is not a toy wrapper around a single `AVPlayer` button. It needs queue behavior, seeking, interruption handling, track transitions, and remote-file support. `AVAudioEngine` gives the app room to behave like a real player rather than a demo.

### Async/Await and Main-Actor Isolation

The app has several places where concurrency could become a fistfight:

- paginated NFT loading
- retry logic and rate limiting
- remote audio downloads
- image generation
- UI state updates

Using Swift concurrency keeps those flows readable, and `@MainActor` on the audio engine is a deliberate guardrail against state races.

### Alchemy/Web3/Wallet-Oriented Networking

NFT ownership and metadata are the spine of the product, so blockchain-facing service code is not an optional add-on. The networking layer exists because the app needs wallet-native data, not generic media content.

### Image Playground

This is where the app gets a little weird in a good way. `HomeTabView` generates wallet-influenced aurora imagery from deterministic prompt atoms. That turns the home screen from "dashboard with a background" into "dashboard with a personalized mood system."

## The Journey

### 2026-03-14: First serious map of the codebase

The first thing that jumps out is that Auralis is really two products braided together:

- a wallet/NFT utility app
- an audio experience built on NFT metadata

That is not a criticism. It is the central fact of the repo.

### 2026-03-14: New code-style rule worth making explicit

One team preference is now clear enough to document as a project rule: avoid `static` functions and `static` stored properties where a regular instance-based design will do the job.

Why? Because too much `static` in Swift starts to smell like JavaScript utility-object thinking:

- behavior drifts away from the state it belongs to
- injection gets harder
- testing gets more brittle
- code starts reading like a namespace dump instead of a model

That does not mean `static` is banned. Real type-level constants and genuinely type-owned APIs still have a place. But in Auralis, the default should be instance-oriented code, small value types, injected dependencies, and local helpers before reaching for `static` as a convenience move.

### War Story: stale async loads are a real danger in audio apps

`AudioEngine` already shows the scars of a real class of bugs: stale async playback requests stomping on newer ones. The `beginNewLoad()`, `currentLoadTask`, and `activeLoadID` flow is basically a nightclub bouncer checking wristbands. If an old task tries to re-enter after a newer request started, it gets thrown out.

That pattern is worth remembering. Media code without cancellation discipline turns into ghost playback, wrong artwork, or tracks switching underneath the UI.

### War Story: NFT APIs are polite until they are not

`NFTFetcher` includes retry logic, backoff, and request throttling. That usually means somebody met rate limits the hard way. The code is doing the right practical thing:

- validate the wallet early
- distinguish retryable from non-retryable failures
- cap total attempts
- keep pagination state explicit

This is a good example of engineering maturity. The happy path is easy; surviving public API mood swings is the real work.

### Aha: the home background is not random wallpaper

`HomeTabView` builds deterministic prompt concepts from:

- wallet address
- chain ID
- selected scene
- style lane

That means the home background is identity-driven. It is closer to a visual fingerprint than a decorative asset. Very easy to miss if you only skim the UI code.

### Pitfall: the repo has active code and fossil code side by side

`MusicApp/OLD/` still exists. That is fine, but it raises the risk of fixing the wrong file during future work. Before changing anything in music playback, confirm whether the modern path goes through:

- `MusicApp/AI/Audio Engine/`
- `MusicApp/AI/V1/`

and not the legacy layer.

### Pitfall: giant files hide responsibilities

`NFT.swift` is doing a lot more than its filename advertises. That creates two dangers:

- contributors may miss relevant code because they stop reading too early
- unrelated edits can collide because too many responsibilities live together

If a future bug feels strangely hard to localize, start by checking whether the "obvious" file name is lying.

### Quiet win: tests are not an afterthought

The playlist tests are a good sign. They cover:

- CRUD behavior
- invalid input handling
- persistence expectations
- concurrent access patterns under `@MainActor`

That makes the playlist subsystem feel like engineered software instead of a hopeful UI convenience.

## Engineer's Wisdom

Several senior-engineer instincts show up in this project, and they are worth preserving:

### 1. Put guardrails around the expensive chaos

The code adds discipline where production apps usually bleed:

- network retries
- rate limiting
- stale async work cancellation
- persistence cleanup

That is the right instinct. Fancy UI is optional. Correctness under bad timing is not.

### 2. Keep a durable local source of truth

Pulling NFTs into SwiftData means the app can behave like a library, not a spinner farm. That is exactly how a browsing-heavy app should think.

### 3. Share services at the shell level when they are truly global

`MainAuraView` owning `NFTService` and `AudioEngine` is pragmatic. These are app-level concerns, not tiny leaf-view helpers. Hoisting them avoids duplicated state and weird lifecycle bugs.

### 4. Determinism is underrated

The wallet-seeded aurora prompt generation is a neat reminder that personalization does not always require opaque machine learning. Sometimes a deterministic hash plus good taste gets you 80% of the magic and 0% of the mystery.

### 5. Tests are strongest when they target behavior, not layout

The playlist suite mostly checks outcomes and invariants. That ages better than UI-coupled tests and gives refactors room to breathe.

### 6. Prefer Swift-shaped design over utility-bucket design

This repo should lean toward instance methods, injected collaborators, and types that own their own behavior. If a proposed change wants a pile of `static` helpers, that is usually a signal to step back and ask whether the design is flattening too much context.

## If I Were Starting Over...

I would keep the product idea, but I would tighten the seams earlier.

First, I would split oversized files by responsibility. `NFT.swift` in particular is carrying too much weight and makes the codebase harder to reason about than it needs to be.

Second, I would define the "modern music path" versus "legacy music path" more aggressively, either by removing dead code or fencing it off with explicit naming. Archaeology is fun until you debug the wrong century.

Third, I would keep leaning into small focused services. The existing service layer is useful, but a few domains still feel like they are one growth spurt away from becoming tangled.

Fourth, I would document the app shell more explicitly: wallet state, selected chain, NFT refresh triggers, and audio engine ownership are central to understanding the app. They deserve first-class documentation because they explain why the app behaves the way it does.

Finally, I would keep the weirdness. The personalized aurora system and NFT-powered audio angle are the parts with flavor. The engineering challenge is not to sand those away. It is to give them cleaner boundaries so the app can stay ambitious without becoming brittle.
