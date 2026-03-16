# Journal

## The Big Picture

Auralis is what happens when a wallet viewer, an NFT gallery, and a music player decide they want to live in the same apartment. The app lets someone bring in an account, pull its NFT world into local storage, and then wander across home, news, gas, and music surfaces without each feature acting like it has never met the others before.

The product has a strong identity layer hiding underneath the glow. If the app does not know which account is active, everything else gets weird fast: NFT refreshes drift, deep links become awkward, and the music side loses the context it expects. A lot of the engineering gravity in this codebase comes from keeping that identity story coherent.

## Architecture Deep Dive

Think of `MainAuraView` as the front desk of a boutique hotel. It checks who you are, which chain you are on, whether your bags have arrived yet, and whether that mysterious deep link should be escorted upstairs now or told to wait in the lobby.

`MainTabView` is the hallway system. It decides which wing of the building you are walking into, but it is not supposed to secretly own identity rules.

`NFTService` is the shipping dock. It receives wallet-specific inventory from the network, cleans it up, and stores it so the rest of the building can pretend everything is tidy.

`AudioEngine` is the house band. It is always around, it needs stable long-lived ownership, and everyone notices immediately when it misses a beat.

For `P0-201`, `EOAccount` is becoming more than a plain address wrapper. It is now the source record for a watch-only roster: where the account came from, when it was added, when it was last selected, and the smallest useful holdings summary we can support in Phase 0 without inventing a full analytics system.

## The Codebase Map

`Auralis/Auralis/Aura/` is the product shell and UI.

`Auralis/Auralis/DataModels/` is where the app’s memory lives. If a type here changes shape, the ripples travel.

`Auralis/Auralis/Networking/` contains fetchers, services, throttling, and the “please do not anger the API” layer.

`Auralis/Auralis/MusicApp/AI/` is the active music path. `MusicApp/OLD/` is the archaeological site.

`Auralis/AuralisTests/` contains Swift Testing coverage for shell logic, helpers, secrets, audio pieces, and now account model behavior.

## Tech Stack & Why

SwiftUI is the obvious choice here because the app is heavily state-driven. Identity changes, loading state, tab routing, and media playback all want to redraw surfaces declaratively instead of juggling view controllers like flaming swords.

SwiftData is doing the local persistence work because the app needs durable account and NFT state, not just a pile of transient structs floating through memory.

Swift Concurrency fits the networking and playback story better than callback spaghetti. The codebase already leans in that direction, and it should keep doing so.

The Testing framework is the right default for unit-style coverage here because the tests read cleanly, parameterization is straightforward, and the intent stays visible instead of drowning in ceremony.

## The Journey

### 2025-11-21: P0-201 Step 1, the model stops being hand-wavy

The first move for watch-only account support was not a shiny UI. It was admitting that `EOAccount` did not actually know enough to support the product decisions already made on paper.

Before this change, an account was basically:

- address
- optional name
- access level

That is enough for “hello world,” but not enough for “show me a persisted roster, sort it by recent selection, remember where each account came from, and carry a tiny holdings summary without making the rest of the app guess.”

So Phase 0 now locks in these additions:

- `source`
- `addedAt`
- `lastSelectedAt`
- `trackedNFTCount`

The subtle but important decision: address persistence behavior did *not* change in this step. That was intentional. Model evolution and identity normalization are related, but bundling them together is how migrations turn into ghost stories.

Also worth noting: legacy decoding now backfills sane defaults. That is one of those quiet engineering chores that feels boring until an older payload crashes the app and ruins everyone’s afternoon.

### 2025-11-21: P0-201 Step 2, the account bouncer gets a clipboard

Step 2 was about taking account rules out of random view files and giving them a single adult in the room.

That adult is `AccountStore`.

It now owns:

- address normalization
- persisted account lookup
- create/select/remove operations
- sorted account listing
- duplicate detection
- duplicate overwrite using delete-and-recreate
- fallback selection after deleting the active account

This matters because before the seam existed, account creation logic was duplicated across typed entry and QR scan flows. That setup works right up until one path lowercases an address, another path does not, and a third path quietly creates a duplicate that looks “basically the same” to a human but absolutely not to persistence.

The nice engineering detail here is the event seam. `AccountEventRecorder` is intentionally tiny and intentionally boring. Right now the default implementation does nothing, which is perfect. It means `P0-201` can move without pretending `P0-501` is already finished. Future receipt logging gets a plug-in point instead of a rewrite.

There was one small bug war story during implementation: the first normalization pass was still too strict and treated inputs like `0Xabc...` as invalid. That immediately showed up in the store tests. The fix was to make normalization lowercased and regex-backed before duplicate checks, so the store now behaves like an actual domain layer instead of a picky string comparer.

## Engineer's Wisdom

Good engineers separate “we decided this” from “we implemented everything around it.” Step 1 of `P0-201` is exactly that move. The model is now opinionated enough to support the rest of the work, but the shell and UI logic are still intentionally untouched until the account seam exists.

Once the seam exists, keep it authoritative. A store that centralizes rules only helps if the app actually stops bypassing it.

Another lesson: when a ticket says “minimal metadata,” believe the word “minimal.” You do not win points by stuffing ten speculative fields into a model because they might be useful one day. That is how simple account records become junk drawers.

Backward compatibility deserves the same seriousness as new features. If older encoded accounts can no longer decode, the app has traded progress for fragility.

## If I Were Starting Over...

I would have introduced an explicit account domain seam earlier, before account creation logic leaked into multiple views. The current `P0-201` plan is correcting that, but it would have been cheaper if the model and orchestration layer had been treated as first-class from the beginning.

I also would have written the account ordering rule down sooner. “Most recent activity” sounds obvious until three people mean three different timestamps.
