# Journal

## The Big Picture

Auralis is what happens when an NFT wallet viewer, a chain-aware dashboard, a receipt timeline, and a music app decide to share one apartment. You bring an address, Auralis restores your scope, fetches and persists the collection, and then lets multiple product surfaces work off that same identity without pretending they live in separate universes.

## Architecture Deep Dive

The app shell is the front desk. `MainAuraView` and `MainTabView` decide who is checked in, which chain they are standing on, and which wing of the building they should be sent to next.

`AccountStore` is the guest book. It normalizes addresses, prevents duplicates, and records account-level actions so the app can explain what happened later.

`NFTService` is the loading dock. It pulls inventory from the network, deals with retries and throttling, then hands clean data to SwiftData for local persistence.

`ContextService` is the concierge clipboard. It gathers current account, chain, freshness, receipt count, and native balance into one snapshot so the chrome and shell UI can speak with one voice instead of improvising conflicting stories.

The receipt system is the black box recorder. When something important happens, the app writes down enough scope and payload detail to reconstruct the story later without forcing every feature to invent its own logging language.

## The Codebase Map

`Auralis/Auralis/Aura/` is the visible product shell: auth, tabs, home, news, search, and shared chrome.

`Auralis/Auralis/Accounts/` holds account persistence and account event recording.

`Auralis/Auralis/Networking/` contains provider seams, NFT refresh orchestration, throttling, and chain-backed reads.

`Auralis/Auralis/Receipts/` is where timeline storage, filtering, and event logging live.

`Auralis/Auralis/MusicApp/AI/` is the active music path. `OLD/` is the attic. Do not assume the attic is load-bearing.

`Auralis/Auralis/DataModels/` is the durable model layer, including `EOAccount`, `NFT`, chain types, and receipt storage models.

## Tech Stack & Why

SwiftUI drives the UI because the app is mostly state choreography: account scope, chain scope, loading state, navigation state, and media state all need to stay in sync without UIKit glue code metastasizing everywhere.

SwiftData handles local persistence because the app wants durable local state for accounts, NFTs, and receipts without building a custom database layer for every feature.

Swift Concurrency is the right fit because network reads, refresh flows, and snapshot building are naturally async tasks, and the codebase already prefers explicit async seams over callback soup.

Receipt-backed event logging exists because this app has a lot of long-lived state. When something feels wrong, “what happened?” is not a philosophical question, it is a product requirement.

## The Journey

### War story: P0-461 started with a route that already existed, but no surface

The first pass through the token-holdings ticket could have gone sideways fast if we had treated “add holdings” like “invent a new token area.” The seam was already there: `ERC20TokensRootView` existed, but it was a polite cardboard sign saying the portfolio surface was not built yet.

The useful discovery was that native balance does not need a new provider abstraction. The app already has one. `ContextService` asks the injected `NativeBalanceProviding` seam for a scope-aware balance and folds it into the shared snapshot. That means the first vertical slice can stay honest: show native balance now, keep ERC-20 rows pluggable later, and avoid building a second balance pipeline that would need to be deleted in a week.

Another important product decision is now explicit: token holdings are expected to be persisted with SwiftData. In other words, the token list should behave more like the app's other durable libraries and less like a temporary network overlay that vanishes the moment a request fails. That matters because “show me what I own” is exactly the kind of feature users notice when it forgets yesterday.

### War story: the first ERC-20 screen is really a persistence exercise disguised as a list

The visible change is an ERC-20 tab that finally shows something useful. The real engineering move is underneath: the new `TokenHolding` model gives Auralis a durable shelf for token balances scoped by account and chain. The first row is the native asset, persisted from the shared shell context snapshot. That sounds modest, but it solves the important failure mode: when the latest provider-backed read does not arrive, the app can still show the last known holdings state instead of shrugging and pretending the wallet is empty.

This is one of those cases where “just render the balance directly” would have been the cheap version and the wrong version. The app already learned that long-lived wallet state needs receipts, scope, and local durability. Token holdings belong in that family too.

### Aha: edge cases got cheaper once the row contract stopped caring where the data came from

Three ugly cases became much easier once the holdings screen was built around a stable row model instead of a direct provider response:

- native-only wallets work because the native row is already a first-class persisted holding, not a special header pretending not to be part of the list
- missing ERC-20 metadata is survivable because the row can render placeholders without assuming symbol or contract detail is present
- scope leaks are easier to catch because the persistence ID and query both speak the same language: normalized account plus chain

That is a useful engineering pattern in this app. If the screen contract is stable before enrichment arrives, partial data feels like an honest early slice. If the screen contract depends on fully enriched payloads, every missing field turns into drama.

### Follow-up still on the board: the app needs a real token-holdings provider call

P0-461 closed the “empty room” problem for the ERC-20 tab, but it did not magically solve ERC-20 discovery. Right now the durable storage shape and UI contract exist, and native balance is persisted into that shape. The missing ingredient is a provider-backed API call that returns token holdings for an account so Auralis can populate real ERC-20 rows.

That follow-up matters because this is exactly where teams accidentally lie to themselves. Once the screen exists, it is easy to start speaking as if “token holdings” are done. They are not. The native-balance-first slice is done. Full account token inventory still needs a network seam, persistence mapping into `TokenHolding`, and the usual scope/freshness/receipt discipline.

### Gotcha: freshness is a shell concern, not a token-screen side quest

It is tempting to let a new holdings screen invent its own “last updated” badge. That would be wrong here. Freshness already lives in the shared context snapshot, and `ReceiptEventLogger` already records context builds with scope metadata. If the holdings surface starts freelancing its own freshness story, the user will eventually see two timestamps arguing in public.

## Engineer's Wisdom

Good seams are usually already present in a mature codebase, just under less glamorous names. Before adding a new service, check whether the existing snapshot builder, router, or receipt system is already carrying the exact contract you need.

Stable row models matter. If v0 native balance and v1 ERC-20 enrichment cannot share the same list contract, the first version was not a vertical slice, it was a throwaway prototype wearing production clothes.

Scope is everything in a wallet app. If account and chain are not attached at the seam, bugs will leak data across contexts and make the UI look haunted.

## If I Were Starting Over...

I would split oversized files like `NFT.swift` earlier. Giant “miscellaneous but important” files are where clarity goes to get lost.

I would also make the token-holdings surface explicit sooner in the shell instead of leaving a placeholder root view in place. A placeholder is fine for a sprint, but after that it becomes camouflage: the route exists, so everyone assumes the feature is somehow more real than it is.
