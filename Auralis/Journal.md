# Journal

## The Big Picture

Auralis is a wallet-aware SwiftUI app that feels a bit like opening a backstage pass for on-chain culture. You bring in an address, Auralis pulls that wallet's NFT world into local storage, and then fans it back out across browsing, music playback, gas tools, and receipts. The app is not just "show me a list"; it is more like a venue with several rooms that all depend on the same guest list.

## Architecture Deep Dive

The app shell is the maître d'. `MainAuraView` decides whether the user should see the front door, the loading hallway, or the main experience. `MainTabView` is the building directory for the major product areas.

`NFTService` is the kitchen expediter. It coordinates fetching, applies scope to every NFT, saves the result into SwiftData, and clears out stale inventory when a refresh completes.

SwiftData is the pantry. The UI does not keep giant in-memory copies of collections forever; instead, views query the local store for the currently active account and chain. That is powerful, but it also means scope bugs can feel spooky: the food is in the pantry, but the waiter is checking the wrong shelf.

## The Codebase Map

The practical landmarks:

- `Auralis/Auralis/Aura/` contains the app shell, tabs, auth, search, home, and newsfeed UI.
- `Auralis/Auralis/DataModels/` holds SwiftData models like `NFT` and `EOAccount`.
- `Auralis/Auralis/Networking/` contains the fetch and refresh orchestration.
- `Auralis/Auralis/MusicApp/AI/` is the active music path.
- `Auralis/Auralis/Receipts/` logs the app's observable paper trail.

If you are debugging "the UI says nothing is there but I know the data exists," start by checking the active scope flowing from the shell into the SwiftData queries.

## Tech Stack & Why

SwiftUI is the obvious fit here because the whole app is state choreography. Tabs, routes, shells, loading, and scoped content all respond to changing account and chain state.

SwiftData is doing the heavy lifting for persistence because the app wants local, queryable NFT state without building a custom database layer from scratch. It is fast to wire into SwiftUI, but it will absolutely punish sloppy identity or scope handling.

Swift Concurrency is the right tool because refreshes, audio loading, and ENS/network work all want cancellation and clean ownership. Callback soup would make this codebase much harder to reason about.

## The Journey

### War Story: The Collection Was There, Until You Opened the Tab

Bug:
Newsfeed and Music could show a blocking "Collection Unavailable" state even after a guest pass successfully loaded NFTs.

What was actually happening:
The tab root views built `@Query` filters in `init` using the current account and chain. That sounds fine until SwiftUI preserves the view instance while the active scope changes. Then the query keeps watching the old shelf in the pantry. The NFTs were persisted correctly, but the query stayed pointed at stale scope values, so the tab behaved like the collection never arrived.

Fix:
In `MainTabView`, the Newsfeed and Music roots now get a scope-based `.id(...)` derived from normalized account address plus chain. When that scope changes, SwiftUI rebuilds those views and recreates the scoped `@Query` with the right filter.

Files touched:
- `Auralis/Auralis/Aura/MainTabView.swift`

How to spot this class of bug again:
If a SwiftUI view creates `@Query` in `init` from bindings or environment-driven scope, ask whether the view is guaranteed to be recreated when that scope changes. If not, you are one stale identity away from a ghost bug.

- Bug squashed: the scoped-identity work for `NFT.Contract` and `NFT.Collection` fixed cross-chain collisions, then immediately introduced a new trapdoor. One refresh can bring back a whole stack of NFTs from the same contract, but the pipeline was still trying to save each token with its own separate `Contract` and `Collection` model object. SwiftData saw a mob of objects all claiming the same unique ID and quite reasonably refused to play along. The result was sneaky: loading finished, Home moved on, and Newsfeed/Music found an empty pantry. The repair was to canonicalize shared child models before insert so one contract node and one collection node can be reused across the whole refresh batch.
- Bug squashed: the guest wallets were so large that the fetcher was accidentally treating successful pages like failed attempts. A wallet with roughly 3,900 NFTs needs around 40 Alchemy pages, but the fetch loop had a global attempt cap that tripped after about 30 page requests even if those requests were succeeding. That is like telling a librarian they may only take 30 steps while shelving a 40-shelf archive. On top of that, if a late Alchemy page returned a 500 after thousands of NFTs were already fetched, the app threw the whole pile away and persisted nothing. The fix was two-part: stop counting successful pages against the retry budget, and keep already-fetched pages when a later page fails so the app can degrade gracefully instead of showing an empty error state.

## Engineer's Wisdom

State bugs in SwiftUI are often identity bugs wearing a fake mustache. When data "exists but doesn't show up," do not start by blaming persistence. First ask:

- What is the active scope?
- Where is that scope converted into a query?
- What guarantees that the view is rebuilt when the scope changes?

That line of thinking is usually faster than adding logs everywhere and hoping the app confesses.

- Shared child models need canonicalization before persistence. If a refresh batch contains twenty NFTs from one contract, the database should see one contract node with twenty references, not twenty lookalikes barging through the same unique door.
- Retry budgets should measure failures, not work completed. If a loop punishes success the same way it punishes errors, a large healthy workload can look identical to a broken one.

## If I Were Starting Over...

I would be stricter about where scoped SwiftData queries are created. Either:

- keep the query unscoped and filter in a thin adapter layer when the dataset is small enough, or
- centralize scope identity so every scoped tab/root view rebuilds predictably.

The current setup works, but only if view identity is treated as part of the data flow contract rather than an incidental UI detail.
