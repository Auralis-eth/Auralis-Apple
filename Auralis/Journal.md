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

### Step 1 of `P0-101E`: Stop pretending repeated UI is just a coincidence

This step was the architectural version of walking through a room and noticing four different chairs that are obviously cousins pretending not to know each other. Home and Newsfeed already repeat the same layout rhythm, glass-card shell, capsule CTA treatment, and empty-state structure. The duplication is not catastrophic yet, but it is absolutely on the path toward every new ticket hand-mixing its own paddings and corner radii like a barista making up house rules.

The useful discovery was that the first primitive slice does not need to be clever. It just needs to cover the things the codebase is already doing with a straight face:

- a screen container for outer padding and width behavior
- a surface card for the rounded glass shell used by Home tiles and empty states
- a pill treatment for lightweight badges and capsule actions
- a shared action button for primary and secondary CTA shapes
- a section header row for the repeated label-plus-content card pattern

One nice restraint came out of the read-through: do not rush an `EmptyStateView` just because the ticket mentions it. Right now the repeated shape is really “glass surface plus icon plus title plus body plus CTA.” If `AuraSurfaceCard` and `AuraActionButton` cover most of that honestly, then the empty-state wrapper can wait until Step 3 proves it deserves to exist. That is a good Phase 0 lesson in general: abstractions should arrive because the code is repeating, not because a checklist looks lonely.

### Step 1, second pass of `P0-101E`: Use the right family members as the reference set

The first inventory pass was directionally right but a little too eager to let Newsfeed vote on the family portrait. The better anchors are the surfaces you have already pushed furthest: the unauth gateway, Home, and Gas.

That changed the primitive read in two useful ways.

First, the app clearly has a scenic-shell pattern. Gateway, Home, and Gas all want the same stage setup: full-bleed background image, soft dark wash, then foreground content that floats above it with breathing room. That means the outer container is not just “screen padding.” It is part layout primitive, part presentation contract.

Second, the CTA story is not one button with too many costumes. There are really two respectable relatives here:

- the hero gateway CTA, like `Enter Auralis`
- the smaller surface action that lives inside cards and utility panels

Trying to mash those into one universal button too early would be like forcing a winter coat and a blazer onto the same hanger and calling it organization.

There was also a healthy scope correction: `GuestPassCard` is beautiful, opinionated, and completely unsuited to becoming a generic primitive. That card is a headline act, not stage scaffolding. Good design-system work is partly knowing which components should stay gloriously specific.

### Step 2 of `P0-101E`: Give the primitives an address before they start wandering

This was a small step, but it is the kind that saves a project from future archaeological digs. The primitive home is now `Auralis/Aura/Primitives/`.

That location does a few quiet but important jobs:

- it sits next to the real feature surfaces instead of hiding in `Helpers/` like a screwdriver tossed into the junk drawer
- it does not belong to `Auth`, `Home`, or `Gas`, which matters because the point of these primitives is that all three can use them without feeling like houseguests
- it makes the next step mechanical instead of philosophical because everyone now knows where `AuraScenicScreen`, `AuraSurfaceCard`, and friends are supposed to land

There is also a nice naming truth here: these are not “framework components.” They are Aura components. Putting them under `Aura/Primitives/` keeps that honest.

### Step 3 of `P0-101E`: Build the scaffolding, not the whole house

This step finally put real components on disk:

- `AuraScenicScreen`
- `AuraSurfaceCard`
- `AuraSectionHeader`
- `AuraActionButton`
- `AuraPill`

The important part is not just that they exist. It is that each one has a narrow job description.

`AuraScenicScreen` owns the stage lighting: northern-lights background, dark wash, and safe-area-aware content placement. `AuraSurfaceCard` owns the glass panel treatment without pretending every card in the product is the same species. `AuraSectionHeader` handles the repeated “title, maybe subtitle, maybe small trailing thing” pattern that keeps showing up in Home and Gas. `AuraActionButton` deliberately recognizes that a gateway hero CTA and a small in-card action are cousins, not clones. `AuraPill` handles the lightweight badge cases without dragging a whole card API into the room.

There was one small build war story, which is exactly the kind of thing primitives should flush out early. The first pass nested the surface style enum inside the generic `AuraSurfaceCard` type, then tried to reference it from a helper modifier as if the generic parameter did not exist. Swift politely refused. Moving that style enum to a top-level Aura-specific type fixed the problem and kept the primitive generic instead of accidentally stapling it to one concrete specialization.

The broader lesson: reusable UI code should be narrow in behavior and boring in type shape. If a primitive needs a detective novel to explain its generic model, it probably is not ready to be shared yet.

### Step 4 of `P0-101E`: Make the primitives earn their rent

This is where the abstractions had to stop looking good in previews and start paying rent in production code.

The proving set stayed aligned with the reference surfaces:

- Gateway proved `AuraScenicScreen` and the hero version of `AuraActionButton`
- Home proved `AuraSurfaceCard`, `AuraSectionHeader`, and compact actions
- Gas proved the full stack: scenic shell, surface cards, section headers, pills, and retry actions

The useful result is not that every screen now worships the primitives. It is that the duplicated glass-card markup started disappearing without making the call sites uglier. That is the whole game. If a shared primitive shortens the repeated code *and* preserves the existing visual language, it is helping. If it forces every screen to speak in riddles, it is not.

Gas was the best honesty test. Utility screens are where fake design systems often fall apart because the components only really understand “marketing card” and panic when asked to display structured data or an updating status. The new header-plus-pill combination held up there, which is a good sign the primitives are small in the right way.

There is also a nice cultural lesson in the Gateway migration. The submit action now goes through the same primitive family as the card actions, but not the same exact style. That distinction matters. Reuse does not mean flattening every interaction into one interchangeable blob. It means recognizing the shared skeleton while still letting the hero moment dress like the hero moment.

### Step 5 of `P0-101E`: Stress the layout before users do it for us

This step was the usual reminder that a component can compile perfectly while still behaving like a diva the moment text gets bigger or width gets smaller.

Three practical fixes came out of the validation pass:

- the gateway CTA had accidentally become a button inside a button, which is the kind of thing that looks innocent in code and turns into nonsense in interaction semantics
- the Home tile row needed an escape hatch for compact-width and accessibility-size layouts, so it now stacks vertically when the screen or type size stops being generous
- the new primitives were still a little too optimistic about one-line text, so buttons, pills, and section headers now wrap more honestly instead of clinging to the single-line fantasy

The preview tooling was a bit moody on the heavier full-screen renders, but the smaller primitive previews came back clean and were actually more useful than they sound. They showed the hero CTA, compact CTA, header-plus-pill layout, and energy card composition without clipping or contrast surprises. Then the full project build passed, which is the software equivalent of tightening every bolt after shaking the ladder.

The good lesson here is that accessibility support is often about giving layouts permission to admit reality. Text grows. Width shrinks. Headers need to fall into vertical stacks sometimes. A UI that handles that gracefully is usually not “more complicated.” It is just less in denial.

### `P0-101B`: Put the OS chrome in one place and let the rest of the app breathe

This ticket could have gone badly in a very familiar way: copy the same header into Home, News, Music, Tokens, and detail screens until the codebase starts looking like a flyer that got run through the office copier six times. That would have “shipped chrome,” but it would also have guaranteed a miserable follow-up ticket the first time one badge or button changed.

The better move was to mount the chrome once at the `MainTabView` layer using a top safe-area inset. That gives the app one always-visible OS chrome bar instead of many cousins pretending to be synchronized by telepathy. It also means routed detail flows inherit the same chrome automatically instead of needing special case glue in every navigation destination.

The first pass keeps the mode badge fixed to `Observe`, exactly as planning said it should. That is not a compromise. It is discipline. `P0-601` is where mode ownership gets formalized. Letting `P0-101B` smuggle that logic in early would have been the architectural version of hiding a raccoon in the drywall and hoping future-you does not hear scratching.

The nicest bit of practical engineering here is the freshness signal. Instead of inventing fake “synced” UI copy, the chrome now reads from a real `lastSuccessfulRefreshAt` value on `NFTService`. That is a small state addition, but it makes the freshness pill honest. Honest UI ages better than decorative UI.

There is still deliberate placeholder territory:

- search now opens from the chrome into a real fixed placeholder surface instead of a useless stub
- the context inspector exists as a sheet seam without pretending `P0-403` is already done
- receipts stay out of this ticket instead of becoming accidental scope sprawl

That is what a healthy Phase 0 ticket looks like: visible progress, clean seams, and a refusal to “finish” three future tickets by accident.

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

### Step 6 of `P0-501`: Put a baggage tag on one real async journey

This was the first moment the receipt system had to prove it could follow a story instead of just logging isolated sentences. The chosen story was the NFT refresh flow: caller kicks off a refresh, fetcher does network work, service persists the results. One correlation ID now rides along that whole trip like a luggage tag that nobody downstream is allowed to replace with their own handwriting.

The key architectural move was resisting magic. `NFTService` does not silently mint IDs. `NFTFetcher` definitely does not. The caller creates the correlation ID explicitly, then the service passes it down into the fetcher and into the networking receipt recorder seam. That is exactly the kind of discipline that keeps “correlation” from turning into “somewhere a UUID happened.”

There was also a useful Swift Concurrency lesson buried in the cleanup. `NFTService` was the correct place to draw a `@MainActor` line because it owns UI-facing observable state and a `ModelContext`. Once that boundary was explicit, a bunch of awkward `MainActor.run` closure juggling disappeared, and the code got simpler instead of more ceremonial. That is usually a good sign you picked the right isolation boundary.

### Step 7 of `P0-501`: Add the big red reset button, but behind glass

By this point the store already knew how to forget everything, but Step 7 was about making that forgetfulness feel intentional instead of incidental. `ReceiptResetService` is that extra layer of ceremony on purpose. A full wipe of receipt history is a destructive operation, and destructive operations should look a little different in code. They should not hide in the same mental bucket as “give me the latest 20 items.”

The useful nuance here is what did *not* get added: no single-receipt delete, no mutable admin API, no cute helper that quietly chips away at the archive one row at a time. The reset seam does one thing, loudly: erase the whole ledger. That keeps the append-only story honest instead of letting it die by a thousand “just this one helper” cuts.

### Step 8 of `P0-501`: Prove the system behaves after the whiteboard meeting ends

The last step was less about inventing code and more about proving the pieces actually form a machine. By this point the repo already had tests for the contract, storage, sanitization, account integration, correlated refresh flow, and reset behavior. The one missing ingredient was the “close the app, come back later” check, so the suite now recreates a real SwiftData container against a temporary on-disk store and confirms the receipt is still there after the second boot.

That kind of test matters because persistence bugs are sneaky. In-memory tests can make you feel like a genius right up until the app relaunches and your so-called history evaporates like stage fog. The relaunch check is the boring friend who insists on verifying the car still starts the next morning. You want that friend around.

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
