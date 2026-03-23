# Journal

## The Big Picture

Auralis is what happens when an NFT wallet browser, a scoped local cache, and a music player all move into the same apartment. The app lets you restore or choose an account, sync wallet NFTs into SwiftData, browse them across multiple shell surfaces, and play the audio-capable ones without treating the media layer like the center of the universe.

## Architecture Deep Dive

The shell works like a train station with one master departure board. `MainAuraView` decides whether the user is still at the ticket counter, waiting for a sync, or already moving through the app. `MainTabView` is the concourse: News, NFTs, Music, Gas, and the rest all branch from the same shared account-and-chain state. `NFTService` is the baggage system behind the wall. It fetches inventory, stamps it with the right scope, saves it, and throws out only the luggage that belongs to the platform currently being cleaned.

## The Codebase Map

`Auralis/Aura/` is the shell and product UI.
`Auralis/DataModels/` holds the SwiftData models and their helper logic.
`Auralis/Networking/` contains NFT fetch orchestration, provider integration, retry logic, and receipts.
`Auralis/MusicApp/AI/` is the active music stack.
`Auralis/Helpers/` is where small but dangerous utility code lives, which is exactly why it needs watching.
`AuralisTests/` is the proving ground for scope, routing, receipts, and provider behavior.

## Tech Stack & Why

SwiftUI is the shell language because the app is fundamentally state choreography. SwiftData is the local memory because wallet inventory needs to survive refreshes and tab switches without hand-rolled storage glue. Swift Concurrency is the traffic cop because fetch, refresh, and playback all have failure modes that get sloppy fast if they drift into callback soup.

## The Journey

One of the nastier bugs in this pass was a classic identity leak: NFTs had chain scope, but not account scope, while the UI was happily querying `NFT` directly. That is like labeling luggage by airport only and then acting surprised when two passengers get the same suitcase. The fix was to make account-plus-chain a first-class scope on `NFT`, stamp it during refresh, and teach every read path to respect it.

Another war story: the retry ceiling in `NFTFetcher` looked defensive but actually lied. Once total attempts were exhausted, the fetch loop could fall out and still record success. That is the software equivalent of a delivery driver marking a package “delivered” because they got tired of circling the block. The new behavior throws a terminal error and records failure instead.

Audio also got demoted from “launch prerequisite” to “subsystem.” That is healthy. If the audio engine fails to initialize, the music tab now shows an unavailable state and the rest of the shell still works. Apps should not explode just because one optional talent did not show up for rehearsal.

## Engineer's Wisdom

Scope is not a comment. If the app cares about account and chain at runtime, the model needs to care too. “We’ll remember the active wallet in the view layer” is how cross-scope leakage starts.

Failure semantics matter as much as success semantics. A refresh that times out, exhausts retries, or cannot initialize audio is still part of the product contract. If the code lies in those paths, the UI will eventually lie too.

Mechanical cleanup is worth doing when an API typo starts spreading. Small inconsistencies age badly because they train the rest of the codebase to copy the wrong thing.

## If I Were Starting Over...

I would make NFT scope explicit on day one and treat direct `NFT` queries as scoped-only APIs from the start. That single decision would have prevented a surprising amount of downstream repair work. I would also isolate “degradable subsystems” like audio behind optional shell contracts earlier, because it is much easier to preserve app stability than to claw it back after a `fatalError` has already become part of the launch path.
