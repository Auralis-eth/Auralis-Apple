# Journal

## The Big Picture

Auralis is what happens if a wallet tracker, an NFT gallery, a gas station, and a music player all agree to share an apartment. The app lets someone bring in a watch-only wallet, pull NFT data, keep it around locally, and then wander through a set of Aura-branded experiences built on top of that identity and media graph.

## Architecture Deep Dive

The app behaves like a hotel lobby with several elevators behind it. `MainAuraView` is the person at the front desk deciding whether you should go to onboarding, loading, or the main floor. `AccountStore` is the keycard desk for watch-only identities. `NFTService` is the concierge that knows how to ask the outside world for collectibles, then hand the results to SwiftData so they stick around after the lights go out. `AudioEngine` is the house band in the corner that somehow never stops playing.

The new receipt contract from `P0-501` is deliberately not another front desk. It is a ledger in the back office. Product seams like `AccountEventRecorder` can drop off facts there, but the UI should never need to know how the filing cabinet works.

## The Codebase Map

- `Auralis/Auralis/Aura/` is the user-facing shell and feature surfaces.
- `Auralis/Auralis/Accounts/` owns watch-only account behavior and the event seam for account-related receipts.
- `Auralis/Auralis/DataModels/` holds SwiftData-backed domain models.
- `Auralis/Auralis/Networking/` handles remote fetches, pagination, throttling, and service orchestration.
- `Auralis/Auralis/MusicApp/AI/` is the active audio path.
- `Auralis/Auralis/Receipts/` now starts to define the app-wide receipt contract for append-only event history.
- `Auralis/AuralisTests/` locks behavior down with Swift Testing.

## Tech Stack & Why

SwiftUI drives the UI because the app is mostly state choreography: onboarding state, selected account state, persisted NFT state, and playback state all need to stay in sync without a pile of manual view wiring.

SwiftData is the persistence layer because the project already leans on it for app models, and `P0-501` explicitly decided receipts should live in the same local persistence world instead of growing a second storage system like an awkward shed in the backyard.

Swift Testing is the right fit for this repo because the test suite wants clear, expressive contracts. It reads more like executable intent and less like a courtroom transcript.

## The Journey

### Step 1 of `P0-501`: Lock the receipt contract

The first trap here was obvious: it would have been easy to jump straight into a SwiftData model and call that “progress.” That would have skipped the hard part, which is defining what a receipt actually is before the persistence layer starts making decisions for us.

The contract now says:

- receipts are immutable historical facts
- the append-only API has create, bounded reads, export, and full reset only
- correlation IDs are caller-owned and never invented by the store
- sanitization is a separate step before persistence, not an apology afterward

That last point matters. If raw payloads go straight into storage and someone promises to redact them later, that promise will eventually lose a fight with a deadline.

## Engineer's Wisdom

Good architecture is often a story about refusing convenience in the right places. A global logger would have been convenient. Letting `AccountStore` write SwiftData receipt rows directly would also have been convenient. Both would have made `P0-701` uglier later.

The better move was to keep the seam narrow:

- product code speaks in product events
- receipt infrastructure speaks in generic append-only records
- sanitization has a named boundary

That is senior-engineer behavior in a nutshell: make the next change easier, not just today’s diff shorter.

## If I Were Starting Over...

I would carve out the receipts area earlier. The app already had a good account seam from `P0-201`, but without a dedicated home for receipt concepts it would be too easy for event history to become “just one more helper” buried in unrelated files. That path usually ends with a junk drawer and a future refactor with a thousand-yard stare.
