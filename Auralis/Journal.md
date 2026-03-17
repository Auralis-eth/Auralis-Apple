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

### Step 2 of `P0-501`: Give receipts a real filing cabinet

This step was less glamorous and more important. A receipt contract living only in pure Swift types is like designing an archive room on a whiteboard and then discovering the building has no shelves.

The new `StoredReceipt` model is the shelf. It stores the locked contract fields in SwiftData and keeps the payload as JSON `Data`. That choice is intentionally boring in the good way. Instead of teaching SwiftData how to natively persist a recursive JSON enum on day one, we store the already-sanitized payload as export-safe bytes and decode it when needed. Fewer moving parts, fewer “why is this transformable field angry?” afternoons.

The key lesson here: persistence shape and API shape are cousins, not twins. The append-only contract still lives at the API boundary. The model just needs to preserve the facts faithfully so the later store implementation can enforce behavior without performing archaeology.

### Step 3 of `P0-501`: Teach the filing cabinet some manners

With the shelf built, the next job was making sure people use it correctly. `SwiftDataReceiptStore` is the librarian here: it decides the next sequence number, hands back recent receipts in bounded slices, exports everything in a deterministic order, and only allows one destructive move: burn the whole archive down with `resetAll()`.

The subtle part is ordering. Timestamps look trustworthy right up until two receipts share the same second or a system clock does something theatrical. That is why the store sorts everyday reads by newest `createdAt` and then newest `sequenceID`, while export walks the other direction so the JSON array reads like a stable timeline instead of a shuffled deck.

There was also a small reminder that tooling has moods. The store compiled cleanly and runtime validation proved the behavior, but the Xcode test runner in this session started canceling tests broadly instead of giving crisp per-test results. That is annoying, but it is not the same thing as the store being wrong. When the harness gets dramatic, a direct executable check is the engineering equivalent of tapping the mic yourself.

### Step 4 of `P0-501`: Install the shredder before anyone stores secrets

The receipt sanitizer is now a real thing instead of a polite protocol waiting for adulthood. `DefaultReceiptPayloadSanitizer` walks the payload recursively and only redacts the two Phase 0 categories we explicitly promised to handle: raw RPC URL fields and raw error string fields. Nothing else gets “helpfully” scrubbed just because it looks suspicious. That restraint matters. Privacy code that redacts too much becomes untrustworthy in a different way because it quietly destroys useful context.

Export also got a small hardening pass: JSON now uses sorted keys so the output is steadier for tests, diffs, and future debugging. Not glamorous, but this is exactly the kind of thing that turns an export feature from “technically works” into “actually usable.”

The war story here is mostly about tooling, again. The project build succeeded and Xcode discovered the new sanitizer/export tests, but the runner kept timing out before returning results. That is a validation limitation of the session, not a sign that the sanitizer contract is vague. The code path itself is straightforward, narrow, and now lives in one place instead of becoming a repo-wide scavenger hunt for string replacement.

### Step 5 of `P0-501`: Swap the fake receptionist for a real clerk

`AccountEventRecorder` finally stopped being a cardboard cutout. The new receipt-backed implementation translates account events into generic receipts and hands them to the store, which is exactly the division of labor we wanted from the start. `AccountStore` still speaks in account events. The receipt layer still speaks in append-only records. Nobody had to pretend those are the same language.

The important design move here was not shoving SwiftData receipt details into `AccountStore`. Instead, the views that already create `AccountStore` now ask for the live account recorder seam. That keeps the dependency pointing the right way: product code depends on the seam, and the seam decides how facts get filed away.

The runtime validation was the satisfying part. A create-select-remove sequence produced three persisted receipts in the expected order: `account.added`, `account.selected`, `account.removed` once you read the timeline oldest-to-newest, or the reverse if you ask for latest-first. That is the kind of check that tells you the seam is no longer decorative.

## Engineer's Wisdom

Good architecture is often a story about refusing convenience in the right places. A global logger would have been convenient. Letting `AccountStore` write SwiftData receipt rows directly would also have been convenient. Both would have made `P0-701` uglier later.

The better move was to keep the seam narrow:

- product code speaks in product events
- receipt infrastructure speaks in generic append-only records
- sanitization has a named boundary
- persistence can use a simple stable representation even when the domain type is richer in memory

That is senior-engineer behavior in a nutshell: make the next change easier, not just today’s diff shorter.

## If I Were Starting Over...

I would carve out the receipts area earlier. The app already had a good account seam from `P0-201`, but without a dedicated home for receipt concepts it would be too easy for event history to become “just one more helper” buried in unrelated files. That path usually ends with a junk drawer and a future refactor with a thousand-yard stare.

I would also decide earlier which parts of a domain model deserve a first-class SwiftData mapping and which parts should stay encoded at the storage edge. Recursive JSON payloads are a classic trap: very expressive in memory, much less fun once a persistence framework wants every corner sanded down.
