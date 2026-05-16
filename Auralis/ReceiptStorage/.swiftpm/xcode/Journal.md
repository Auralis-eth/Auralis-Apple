# Auralis Learning Journal

## The Big Picture

Auralis is a wallet-centered SwiftUI app: it helps people bring a wallet into the app, discover NFT-backed media and account activity, and move through Aura-branded surfaces like Home, News, Gas, Music, Tokens, and receipts. Think of it like a control room for an on-chain identity, with SwiftData quietly keeping the local logbook.

## Architecture Deep Dive

The app is split into focused packages so each kitchen station has a job. `AuralisPrimaryModels` owns the ingredients, `ReceiptsCore` defines the receipt contract, `ReceiptStorage` cooks those receipts into SwiftData, and `SwiftDataAdapters` provides shared mutation tools. The receipt store itself uses a model actor as the back-room clerk that writes records and hands out sequence numbers.

The important detail: sequence numbers are state, not just math. If two clerks track the same receipt cabinet with separate counters, one can clean the cabinet while the other still thinks the next ticket is number three.

## The Codebase Map

- `AuralisPrimaryModels/` holds shared model types such as `StoredReceipt`, `Chain`, accounts, NFTs, and payload values.
- `ReceiptsCore/` defines receipt protocols, payload sanitizing, event logging, and reset contracts.
- `ReceiptStorage/` provides the SwiftData-backed receipt store and reset service.
- `SwiftDataAdapters/` contains reusable `ModelContext` mutation helpers for save/rollback discipline.

## Tech Stack & Why

- SwiftUI gives the app a state-driven UI model that matches wallet, route, and playback state well.
- SwiftData stores local domain records without dragging Core Data ceremony into every feature boundary.
- Swift Testing keeps package tests small, readable, and async-friendly.
- Swift Concurrency keeps persistence and service boundaries explicit through actors and async APIs.

## The Journey

### Receipt reset sequence cache bug

A reset test caught a sneaky persistence bug: receipts were deleted, but the next appended receipt got sequence ID `3` instead of restarting at `1`. The store's model actor had cached the next sequence number after appending two receipts. The reset service created another store for the same SwiftData container, so it cleaned storage but did not clear the original actor's warm counter.

The fix was to share the receipt persistence actor by `ModelContainer`, not by whichever wrapper happened to ask for a store. Now the counter lives with the storage lifetime, like keeping one deli ticket machine at the counter instead of letting every employee carry their own.

## Engineer's Wisdom

When a cache mirrors persistent state, its ownership has to match the persistence boundary. If reset deletes the database but not the cache, the app enters a weird half-reset state that tests often expose before users do.

The practical habit: follow the lifetime. Contexts can be lightweight wrappers, but containers represent the actual store. Cache by the thing whose lifetime you mean.

## If I Were Starting Over...

I would make sequence allocation an explicit collaborator from the first implementation and test reset behavior through two store instances. Bugs involving shared persistence almost always hide in the space between "same data" and "same object."