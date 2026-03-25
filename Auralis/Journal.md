# Journal

## The Big Picture

Auralis is a wallet-aware NFT app with a split personality in the best way: part collector dashboard, part on-device activity log, and part music player for NFT-backed media. The app’s real job is to take a wallet scope, pull in what matters, keep it locally intelligible, and let the user move around without feeling like they just opened a blockchain spreadsheet.

## Architecture Deep Dive

Think of the app like a hotel with one front desk and several wings.

- `MainAuraView` is the front desk. It decides whether the guest is still checking in, waiting on luggage, or ready to roam the building.
- `MainTabView` is the hallway map. It routes people into Home, News, Gas, Music, Receipts, and the token surfaces.
- The receipt stack is the security camera archive. It does not change history; it records facts, keeps them ordered, and lets later features replay what happened without inventing new stories.
- `NFTService` is the back-of-house coordinator. It talks to the network layer, updates local persistence, and keeps the visible library from drifting away from the active wallet scope.
- `AudioEngine` is the resident DJ booth: long-lived, stateful, and very unhappy if you poke it with throwaway ownership patterns.

## The Codebase Map

- `Auralis/Aura/`: the shell, tabs, auth flow, and product-facing SwiftUI surfaces.
- `Auralis/Accounts/`: watch-only account persistence plus account event recording.
- `Auralis/Networking/`: NFT fetch orchestration, providers, throttling, and refresh receipts.
- `Auralis/Receipts/`: receipt contracts, persistence, sanitization, and now the timeline/detail UI model.
- `Auralis/MusicApp/AI/`: the active music experience and shared playback engine.
- `AuralisTests/`: Swift Testing coverage for routing, receipts, shell logic, and service behavior.

## Tech Stack & Why

- SwiftUI: because the app is shell-heavy and state-driven, so declarative navigation and view state are the least painful path.
- SwiftData: because receipts, accounts, playlists, and NFT-adjacent local state need persistence without dragging in a bigger storage framework for Phase 0.
- Swift Concurrency: because the app does real asynchronous work and callback soup would turn the shell into a swamp quickly.
- OSLog: because receipt failures and network coordination need breadcrumbs that survive beyond a single debug session.

## The Journey

- The receipt foundation landed before the real timeline UI. That was the right call. Building the archive before the archivist meant later tickets could work with append-only facts instead of retrofitting schema every time a feature wanted history.
- `P0-503` exposed a classic trap: the shell already had a Receipts tab, so it looked “done” from ten feet away. Up close it was a postcard, not a timeline. The fix was to move filtering, search, and pagination into a dedicated state model so the view did not become a storage-shaped blob.
- Then came the sneakier bug: the Receipts screen wore the active wallet and chain like a name tag, but underneath it was still reading from the whole room. That is the software equivalent of a mislabeled security camera feed. The fix was to make timeline scope an actual filtering boundary, teach receipts to remember wallet and chain hints when they can, and fall back to decoding those hints from older payloads so existing local history did not suddenly become invisible.
- Another gotcha: this repo has both repo-root and project-root `Auralis` segments. That is the kind of naming symmetry that looks tidy until you add a file and realize you have built a beautiful feature in the wrong hallway.

## Engineer's Wisdom

- Keep append-only history append-only. The moment a logging surface quietly starts mutating records, every downstream diagnostic becomes suspect.
- Router state should stay centralized. If every tab starts inventing its own navigation side-channel, deep links and scope resets become whack-a-mole.
- A useful timeline is not just “a list of rows.” It needs opinionated defaults, obvious filters, and a detail view that turns payload JSON into something a human can parse without coffee and a prayer.

## If I Were Starting Over...

- I would separate receipt presentation types from persisted models earlier. That boundary became necessary the moment search and filter behavior wanted value semantics and tests.
- I would add the project journal on day one instead of waiting for the repo to accumulate enough phase tickets to deserve a field guide.
