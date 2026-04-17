# Journal

## The Big Picture

Auralis is what happens when an NFT wallet explorer, a polished dashboard, and a music player decide to share an apartment instead of living in separate apps. You connect an address, the app pulls in wallet context and NFT inventory, then turns that data into several product surfaces: home, newsfeed, gas tools, token views, receipts, and music playback.

The important part is that this is not a “show a list and call it a day” app. It has a real shell, real persistence, real routing, and a long-lived audio engine. It behaves more like a small operating system for an NFT-centric account than a toy demo.

## Architecture Deep Dive

Think of the app like a boutique hotel:

- `MainAuraView` is the front desk. It decides whether you are checking in, waiting for your room, or already headed upstairs.
- `AppRouter` is the concierge. It knows where each tab can take you and keeps the navigation mess from spilling all over the lobby.
- `NFTService` is housekeeping plus logistics. It fetches inventory, cleans stale data, and keeps SwiftData in sync.
- SwiftData is the storage room. It remembers what the network already told us so the app does not behave like it has goldfish memory.
- `AudioEngine` is the resident DJ booth. It stays alive across the app and keeps playback state coherent while views come and go.
- The home presentation logic is the lighting designer. It takes account state, pinned actions, and chain context and turns them into the polished Aura home experience.

The recurring pattern is deliberate ownership. The shell owns long-lived services, feature views receive focused inputs, and logic objects do presentation shaping instead of bloating every SwiftUI view with conditionals and formatting code.

## The Codebase Map

- `Auralis/Aura/`
  The main product shell and UI surfaces.
- `Auralis/Accounts/`
  Account persistence and wallet-facing mutations.
- `Auralis/Networking/`
  Provider abstractions, NFT fetches, ENS support, and token/gas plumbing.
- `Auralis/DataModels/`
  Shared persisted/domain models. Also, occasionally, a file that forgot what its job was.
- `Auralis/MusicApp/AI/`
  The active music experience and audio engine path.
- `Auralis/Receipts/`
  Audit-style event and receipt timeline views.
- `AuralisTests/`
  Contracts, state logic, and feature behavior checks.

If you are navigating this repo for the first time, start at `MainAuraView`, then `MainTabView`, then whichever feature surface you care about. That path gives you the real call graph instead of archaeological artifacts.

## Tech Stack & Why

- SwiftUI
  Because the app is heavily state-driven and has many presentation surfaces that benefit from declarative composition.
- SwiftData
  Because local persistence matters here, and the app wants models close to SwiftUI instead of a hand-rolled persistence layer for every feature.
- Swift Concurrency
  Because networking, refresh flows, and audio coordination are easier to reason about with structured async work than callback spaghetti.
- AVFoundation
  Because eventually somebody has to actually play the music instead of just admiring the cover art.
- Routing and presentation helpers
  Because once a shell grows past a couple tabs, ad hoc navigation state turns into a junk drawer fast.

## The Journey

### Dead Code Sweep

We removed four confirmed-unreferenced UI leftovers after a project-wide reference audit:

- `Auralis/DataModels/TagViews.swift`
- `Auralis/Aura/Auth/LoginTitleView.swift`
- `Auralis/Aura/Newsfeed/ConnectWalletView.swift`
- `Auralis/MusicApp/AI/V1/DetailView.swift`

This was a nice reminder that “file exists” is not the same thing as “feature exists.” `TagViews.swift` was the most interesting one: it looked substantial, but the entire view stack was orphaned. It was basically a fully furnished apartment with no doors leading into it.

We validated the cleanup with a full project build, which passed. That matters because dead SwiftUI can still be accidentally wired through previews, test helpers, or stale project references. In this case, the build agreed with the grep pass: the code was just sitting there, haunting the place.

### Dead Code Sweep, Round Two

A second pass removed more truly orphaned files:

- `Auralis/DataModels/NFTAnimation.swift`
- `Auralis/DataModels/NFTExamples.swift`
- `Auralis/MusicApp/AI/Audio Engine/Playlist/PlaylistStore.swift`
- `Auralis/NFTMetadataAnalyzer.swift`

This round was more interesting because some “unused” code was only unused by the app, not by the test target. `Password.swift` and `ReceiptResetService.swift` looked dead at first glance, but both still have test coverage hanging off them. That is exactly the kind of trap that turns a cleanup into a stealth regression if you move too fast.

The practical lesson: dead in production code and dead in the repository are not the same thing. Sometimes a file is no longer in the product path but is still part of the test contract. If you want it gone, the right move is to remove or rewrite the tests intentionally, not pretend the dependency is not there.

### Aha! Moment

Misleading filenames are a real tax. `NFTImageView.swift` looked suspicious until inspection showed it still houses live support types like `CachedAsyncImage` and `ImageLoader`. The filename was stale; the code was not. Good cleanup work is less “delete everything dusty” and more “confirm which dust is load-bearing.”

### Pitfall

Do not assume a file named like a feature entry point still contains the feature entry point. This codebase has a few places where a file’s name reflects its past life, not its current contents.

## Engineer's Wisdom

- Dead code removal is only “safe” after verifying inbound references and then building the project. Grep without validation is guesswork.
- Large files attract unrelated responsibilities over time. That is how you end up with domain models living next to abandoned UI experiments.
- The cleanest architecture in the world still loses clarity if old view stacks are left behind after a routing refactor.
- A senior-engineer move here is to treat code archaeology as part of product quality, not as a cosmetic chore.

## If I Were Starting Over...

I would put stricter boundaries around feature folders and refuse to let exploratory UI land in `DataModels/`. That one choice would have prevented at least one confusing dead-code pocket.

I would also add a lightweight periodic hygiene pass:

- scan for declaration-only view types
- look for files with zero inbound references
- check whether filenames still match their primary exported types

That is the software equivalent of cleaning the garage before you start storing motorcycles in it.
