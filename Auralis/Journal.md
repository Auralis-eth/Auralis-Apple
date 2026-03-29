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

- a few placeholder-safe preference/module fields whose owning surfaces are not finalized yet
- any final freshness-policy cleanup if ownership changes later

### P0-301 Graduated From "Good Protocols" To "Real Product Plumbing"

There is a common architecture trap where a team builds beautiful protocols, pats itself on the back, and then never routes any real product behavior through them. That is how you end up with a very elegant abstraction and exactly zero users benefiting from it.

`P0-301` was in danger of becoming that story. The repo already had the provider protocols and centralized endpoint resolution, but native balance was still sitting in the corner like a gym membership card: technically useful, rarely exercised.

This pass fixed that by:

- making the shell service hub own one shared read-only provider factory
- routing NFT inventory creation through that factory story
- keeping gas on the same provider-configuration spine
- feeding native balance into `ContextService`, which means the shell context contract now consumes provider-backed data for real

That is the difference between \"we have an abstraction\" and \"the abstraction is carrying weight.\"

### The Loading Screen Was Telling A Half-Truth

The NFT loading screen had a magician's-assistant problem: it was showing one part of the act while the hard work was happening offstage.

The progress bar came from `NFTFetcher`, which only knows about provider pagination. Meanwhile, `MainAuraView` kept the loading screen up until `NFTService` finished the rest of the pipeline:

- metadata parsing
- scope canonicalization
- SwiftData inserts and saves
- stale-item cleanup

So the app could honestly say \"3100 of 3908 loaded\" and still sit there for a while, which looks suspiciously like a hung API call even when the network part is already done.

The fix was to make the refresh pipeline admit what phase it is in. `NFTService` now exposes explicit stages for:

- fetching from the provider
- processing metadata
- saving the collection
- final cleanup

There was a second trap hiding behind that first one: `NFTService` is main-actor isolated, so changing the phase and immediately doing a big chunk of synchronous work meant SwiftUI often could not repaint before the next phase had already started. The code now yields at each phase boundary so the screen can actually show the new status before the next batch of work blocks the lane again.

This is a classic observability lesson: if one number is standing in for four different kinds of work, users will assume the worst and engineers will end up debugging ghosts. It is also a good reminder that in UI code, "the state changed" and "the user saw the change" are not the same thing.

### Shell Context: Stop Letting The Chrome Freelance

Another small but important cleanup landed in the shell spine work. The app already had `ContextSnapshot`, but a few chrome and shell-adjacent paths were still doing the engineering equivalent of calling a teammate instead of checking the source of truth.

Two examples:

- the chrome mode badge was still leaning on `modeState` directly instead of the shared snapshot contract
- `MainTabView` was reaching into SwiftData itself just to count playlists and scoped receipts for context assembly

Neither of those is a production fire by itself. Together, they are how a shell slowly turns back into folklore.

This pass tightened that up by:

- moving chrome mode and context accessibility labels onto `ContextSnapshot`
- adding a shell-facing library-context provider seam in `ShellServiceHub`
- routing the context library counts through that seam instead of teaching `MainTabView` about `Playlist` and `StoredReceipt` fetch details
- letting the empty NFT library state describe the active snapshot scope when that context is already available

The key lesson is boring in the best possible way: once you introduce a shared context contract, do not let the shell keep smuggling in side facts through the kitchen door. If a view needs shell truth, the first question should be, "can the snapshot already say this?"

What is still intentionally not solved here:

- freshness-pill interaction behavior from `P0-101C`
- receipt linkage inside the inspector from `P0-403`
- full compile-time anti-bypass enforcement from `P0-701B`

That is good restraint, not unfinished homework disguised as architecture.

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
