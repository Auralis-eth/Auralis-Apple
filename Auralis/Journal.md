# Journal

## The Big Picture

Auralis is what happens when a wallet explorer, a local activity ledger, a gas dashboard, and a music player all agree to share one shell. The app takes a watch-only wallet and chain scope, builds a trustworthy local picture of that world, and then lets the user move through Home, Search, News, Receipts, Tokens, and Music without the surfaces disagreeing about what reality is.

## Architecture Deep Dive

`MainAuraView` is the front desk. It decides whether the user sees onboarding, loading, or the mounted app shell.

`MainTabView` is the lobby. It keeps the global chrome visible while routing users into the different product wings.

`ContextService` is the translator. Instead of every screen grabbing account, chain, freshness, and counts from random places, the shell builds one `ContextSnapshot` and lets multiple surfaces read the same sentence.

`ShellServiceHub` is the breaker panel. If a feature needs persistence, receipts, providers, policy, or local preferences, it should plug into the panel instead of running an extension cord straight into a lower layer.

## The Codebase Map

`Auralis/Aura/` is the user-facing SwiftUI shell.

`Auralis/Accounts/`, `Auralis/Networking/`, and `Auralis/Receipts/` hold the state and service guts.

`Auralis/AppContext.swift`, `Auralis/ContextService.swift`, and `Auralis/AppServices.swift` are the shell contracts and dependency seams.

`Auralis/MusicApp/AI/` is the active music path. `Auralis/MusicApp/OLD/` is the attic.

## Tech Stack & Why

SwiftUI fits because the product is a pile of stateful surfaces reacting to shared shell state. SwiftData fits because the app wants durable local truth for accounts, receipts, NFTs, token holdings, and playlists. Swift Concurrency keeps the async work readable, especially where stale refreshes and stale audio loads need to stop politely instead of stomping new state.

## The Journey

Latest war story:
four tickets looked “almost done,” which is dangerous territory. That usually means the architecture is 90% there and the product still feels like a draft.

`P0-401` was the classic example. The context schema knew the idea of pinned items, but the field was basically a cardboard cutout. That is how contracts start lying. The fix was to give Home a real pinned-items store, route it through `ShellServiceHub`, and feed the count into `ContextSnapshot`.

`P0-102A` had a similar smell. Home already had modules and shortcuts, but “quick links” was still hiding inside another section like it snuck in through the side door. Pulling quick links into an explicit dashboard section made the surface read like a finished product instead of a staging area.

`P0-101C` needed one final honesty pass too: freshness and scope mattered, but chrome mostly whispered them through accessibility labels and the inspector. Now the chrome shows real freshness and scope state visibly, which is much more useful to actual humans.

## Engineer's Wisdom

If a shared schema field is placeholder-only, either remove it or give it a real owner. Leaving it around “for later” is how a clean contract slowly turns into fiction.

Another lesson:
dependency-injection seams are not just for giant services. Even a tiny local-preference store earns its keep when the same truth has to show up in Home, context, and tests without copy-paste nonsense.

## If I Were Starting Over...

I would have introduced the pinned-preference seam as soon as Home first gained shortcuts. That would have avoided the awkward middle period where the schema claimed to know about pinned items but had no honest way to answer the question.

I would also have made the chrome show freshness visibly from day one. If context matters enough to deserve a ticket, it matters enough to be seen without opening a sheet.
