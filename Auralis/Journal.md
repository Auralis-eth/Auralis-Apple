# Journal

## The Big Picture

Auralis is what happens when a wallet explorer, an NFT gallery, and a music player decide to share an apartment. You give it an account, it pulls in wallet-scoped NFTs, keeps them locally with SwiftData, and then lets different parts of the app reuse that same collection for browsing, routing, receipts, and audio playback.

The app is not a neat little “tap button, get table view” toy. It is a stateful shell with a few moving trains:

- wallet and chain identity
- NFT refresh and persistence
- receipt logging
- a long-lived audio engine
- SwiftUI tabs that all assume the shared state is telling the truth

When one of those trains lies, the whole station gets weird.

## Architecture Deep Dive

Think of the app like a hotel with one front desk and several specialty floors.

- `MainAuraView` is the front desk. It decides who is checked in, which chain they’re on, and where they should be routed next.
- `NFTService` is housekeeping plus inventory. It refreshes what exists for a wallet, writes it to storage, and clears out stale records when it is safe to do so.
- `NFTFetcher` is the loading dock. It talks to providers, handles pagination, retries, throttling, and the awkward reality that networks do not care about your demo.
- `SwiftData` is the storage basement. Useful, but only if every floor agrees which basement they’re using.
- `AudioEngine` is the DJ booth. It needs stable ownership, clean cancellation, and enough paranoia to ignore stale work that finishes late.

The main lesson from this round of fixes: async code is less like a straight hallway and more like a restaurant kitchen. Orders can come in fast, cooks can be interrupted, and if you do cleanup before the plate is actually ready, you throw out tonight’s dinner and yesterday’s leftovers at the same time.

## The Codebase Map

- `Auralis/Auralis/Aura/`
  The app shell, auth flow, home experience, and most user-facing SwiftUI.
- `Auralis/Auralis/DataModels/`
  SwiftData models and large domain types. `NFT.swift` is not just an NFT file. It is a small suburb.
- `Auralis/Auralis/Networking/`
  Provider integration, refresh orchestration, throttling, and error classification.
- `Auralis/Auralis/Receipts/`
  Structured event history for refreshes and resets.
- `Auralis/Auralis/MusicApp/AI/`
  The active music UI and audio engine.
- `Auralis/Auralis/Helpers/`
  Parsing, URL normalization, metadata utilities, and the kind of code that quietly decides whether images appear at all.

## Tech Stack & Why

- SwiftUI
  Because the app is heavily state-driven, and the shell/tab/router model benefits from declarative updates more than it benefits from hand-managed UIKit glue.
- SwiftData
  Because the app wants local persistence that can be queried directly from SwiftUI surfaces without building a custom storage layer for every feature.
- Swift Concurrency
  Because refreshes, playback loading, provider retries, and image generation all involve asynchronous work, and callback pyramids would turn this codebase into soup.
- AVFoundation
  Because audio playback still lives in the real world, where timing, buffering, and interruption handling matter.

## The Journey

### War Story: The Refresh That Could Eat Your Collection

One bug lived in `NFTService` and had bad instincts. It could decide a refresh was “complete enough,” delete NFTs that were missing from the current batch, and only afterward try to save the fresh results. That is exactly backward.

The fix was:

- save refreshed NFTs first
- only run stale-record cleanup after pagination is actually complete
- surface persistence failures instead of logging them and pretending everything is fine

This is the classic warehouse mistake: don’t throw out the old shipment until the new shipment is physically on the shelf.

### War Story: Cancellation That Looked Like Success

`NFTFetcher` could break out of pagination on cancellation and still record the whole operation as a success. That is less “robust telemetry” and more “fiction.”

The fix was:

- convert cancellation into `CancellationError`
- stop the success recorder from running on cancelled work
- run retry decisions against normalized errors, not the raw underlying value

If the mission was aborted, the mission was not accomplished. The logs should not gaslight the UI.

### War Story: The Audio Load Race

`AudioEngine` had the classic stale-task problem: a newer playback request could start, and an older request finishing late could still interfere with the shared task slot and stale-load bookkeeping.

The fix was:

- thread the caller’s `loadID` through the private load path
- only clear `currentLoadTask` if the finishing task still owns that slot

In plain English: only the current bartender gets to close the tab.

### War Story: Two Basements, One Playlist

The music feature had its own nested SwiftData container for playlists, while the app shell already had a shared container. That is how you end up with two basements and a lot of confused staff.

The fix was:

- move `Playlist` into the app-level model container
- remove the feature-local container from the music view subtree

One app, one persistence graph.

### Aha Moments

- Cleanup order matters more than cleanup code.
- Actor isolation solves a lot, but it does not magically protect you from stale logical ownership.
- Deterministic product behavior is easy to accidentally sabotage with one `randomElement()`.
- Accessibility regressions often start as “just use `onTapGesture` for now.”

## Engineer's Wisdom

- Treat cancellation as a first-class outcome, not an error-shaped shrug.
- Shared persistence should be shared on purpose. If a feature creates its own container, assume there is a real cost unless proven otherwise.
- In async systems, “late success” can be a bug. Staleness checks are not decorative.
- UI state that is supposed to dismiss must be backed by mutable state, not a constant binding dressed up as one.
- Deterministic product logic should stay deterministic all the way down. One random branch is enough to make users think the app is unstable.

## If I Were Starting Over...

- I would split `NFT.swift` into actual domain-sized files much earlier. Right now it behaves like a junk drawer with excellent intentions.
- I would make refresh completion an explicit state machine instead of inferring “done enough” from counters and cursors.
- I would centralize image loading and downsampling earlier, because NFT media is chaotic and memory spikes are not a personality trait.
- I would decide upfront which models belong to the shared SwiftData container so feature code never has to improvise persistence boundaries later.

## Latest Entry

Date: 2026-02-08

Today’s fixes tightened the app in the places where state lies hurt the most:

- NFT refresh now saves before cleanup and only deletes stale records after a fully completed refresh.
- Cancelled fetches no longer masquerade as successes.
- Audio playback load sequencing is now guarded against stale completions clobbering the active task.
- Playlists now live in the app’s shared model container instead of a feature-local one.
- Home image generation is user-driven and guarded against overlapping generations.
- Profile avatar prompt generation is deterministic again.
- Several tappable surfaces were converted from gesture handlers to real buttons for accessibility.
- Base64 JSON token metadata decoding now uses `JSONDecoder`, which means valid payloads can actually be read.
