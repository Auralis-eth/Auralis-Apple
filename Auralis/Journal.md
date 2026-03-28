# Journal

## The Big Picture

Auralis is a wallet-aware SwiftUI app that acts like a control room for NFT identity, browsing, receipts, gas context, and music playback. The simplest way to explain it is: you bring a wallet address in, and the app turns that into a long-lived personal surface with history, media, and context stitched around it.

It is not a tiny single-screen demo. It is more like a hotel lobby with several wings: onboarding, shell chrome, search, receipts, NFT browsing, token surfaces, and music. The trick is making all of those wings feel like one building instead of a pile of disconnected rooms.

## Architecture Deep Dive

The app shell works like an airport tower. `MainAuraView` owns the high-level traffic: active account, active chain, restore flow, deep links, and app-level services. `MainTabView` is the terminal map. It decides which major surface the user is in, but it is not supposed to become the source of truth for everything interesting.

`NFTService` and the related networking types are the cargo pipeline. They fetch, retry, cache, and persist NFT data without making the UI learn transport details. `AudioEngine` is the long-lived house band in the basement: once started, it keeps playing while the rest of the building changes screens.

The newer context work is the app's clipboard for "what is true right now?" `ContextSnapshot` is the typed note passed around the shell so views stop free-styling their own interpretation of account, chain, freshness, and local pointers. Without that, every screen starts behaving like a different witness at the same trial.

## The Codebase Map

- `Auralis/Auralis/Aura/` is the visible product shell and feature UI.
- `Auralis/Auralis/DataModels/` is the persistence and domain layer, with a few files that are doing more work than their names admit.
- `Auralis/Auralis/Networking/` is the fetch-and-refresh machinery.
- `Auralis/Auralis/Receipts/` is the audit trail system.
- `Auralis/Auralis/MusicApp/AI/` is the active music path.
- `Auralis/AuralisTests/` is where the contracts are supposed to get caught before production does the yelling.

Practical navigation rule: if a shell behavior feels "global", start with `MainAuraView`, `MainTabView`, `ContextService`, and `AppServices` before spelunking deeper.

## Tech Stack & Why

- SwiftUI because the app is heavily state-driven and the shell is easier to reason about when views are projections of state instead of delegate soup.
- SwiftData because local persistence is not optional here. Accounts, receipts, NFTs, and playlist data all want a real on-device home.
- Swift Concurrency because refreshes, deep-link timing, and cancellation are real problems in this app. Old-school callback chains would turn this into spaghetti quickly.
- Testing framework for unit-style coverage because a lot of the Phase 0 work is about contracts and sequencing, not just pixels.

## The Journey

### War Story: The Context Snapshot Started Life As A Polite Placeholder

`P0-401` began with the right idea and a slightly too-optimistic implementation. The schema types existed, but several fields were still acting like cardboard stand-ins. If the app already knew about playlists or scoped receipts locally, the snapshot still shrugged and returned `nil`.

The fix was not "invent more fake data." The better move was to feed the snapshot only from local truths the app already owned:

- playlist count from local SwiftData
- scoped receipt count from stored receipts
- guest-pass/demo state from the active account source

That moved the context schema from "diagram on a whiteboard" to "contract with actual local teeth."

### Another Good Lesson: Environment Timing Matters

Trying to read `modelContext` directly inside `MainTabView`'s initializer produced a classic SwiftUI trap: escaping closures captured `self` before initialization was complete. The fix was simple once the shape was clear: pass `ModelContext` in from `MainAuraView`, where it already exists cleanly, instead of trying to reach into the environment too early.

That is a very senior-engineer kind of move: do not outsmart initialization rules when composition can solve the problem directly.

### Current P0-401 Reality

What landed:

- stronger `ContextSnapshot` inputs
- more visible context inspection in chrome
- real local library pointers where local data already exists
- explicit notes about what is still deferred

What is still deferred:

- provider-backed native balance summary
- any final freshness-policy cleanup if ownership changes later

## Engineer's Wisdom

Good engineering in this project usually means refusing fake certainty.

- If data is local and real, expose it.
- If data is not ready yet, keep the field placeholder-safe and say so out loud.
- If a dependency note and a newer completion report disagree, trust the newer artifact and update the planning docs.
- If shell state starts leaking into many views as ad hoc values, stop and build a contract before entropy wins.

The codebase keeps rewarding one habit in particular: keep ownership obvious. Who owns mode? Who owns account scope? Who owns context? When the answer is fuzzy, bugs show up as "weird UI state" instead of nice honest compiler errors.

## If I Were Starting Over...

I would introduce the shared context contract earlier. A lot of Phase 0 planning churn came from multiple pieces of UI carrying similar-but-not-identical truth about account, chain, freshness, and shell state. That is how teams accidentally build three dashboards that all claim to be canonical.

I would also shrink some oversized files sooner, especially the ones that quietly became neighborhoods instead of houses. Big files are not automatically bad, but they do hide responsibility creep very effectively.

Finally, I would make the "status artifact hierarchy" explicit from day one:

1. completion report or handoff note wins
2. current strategy file comes next
3. old dependency note loses if it disagrees

That one rule would have saved a surprising amount of archaeological work.
