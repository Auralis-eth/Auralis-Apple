# The Big Picture

Auralis is what happens when a crypto wallet, an NFT gallery, a gas tracker, and a music player all decide to move into the same apartment and somehow make it work. The app lets someone bring in a wallet, pull down NFT data, keep that data around with SwiftData, and then explore it through several product surfaces that all need to agree on the same identity and state.

# Architecture Deep Dive

Think of the app like a hotel lobby with a very opinionated front desk. `MainAuraView` is that front desk. It decides whether a user should see the gateway, a loading state, or the main tab shell. Behind that, `NFTService` is the logistics team hauling in NFT inventory, `SwiftData` is the storage room, and `AudioEngine` is the house band that somehow keeps playing while the rest of the building changes around it.

The key architectural trick is shared ownership without state soup. Wallet identity, persisted models, routing, and audio playback all have long enough lifetimes that they cannot be treated like disposable local view state. That is why the shell owns the durable pieces and passes them down instead of letting each feature spin up its own parallel universe.

# The Codebase Map

If you are navigating this codebase for the first time, here is the street map:

- `Auralis/Auralis/Aura/` is the product shell and most of the user-facing SwiftUI.
- `Auralis/Auralis/DataModels/` holds domain and persistence models.
- `Auralis/Auralis/Networking/` handles fetches, throttling, retries, and service orchestration.
- `Auralis/Auralis/MusicApp/AI/` is the active music stack.
- `Auralis/Auralis/MusicApp/OLD/` is the attic. Do not assume the dusty boxes up there are wired into the house.
- `Auralis/Auralis/Receipts/` contains receipt-related contracts, sanitizing, and persistence support.

# Tech Stack & Why

SwiftUI is the UI layer because the app is heavily state-driven and wants a clear data flow more than handcrafted view controller choreography. SwiftData is the persistence layer because the app stores local NFT and related records and benefits from a native model system that plays well with SwiftUI. Swift Concurrency is the preferred async model because network refreshes, media loading, and state restoration become easier to reason about when they read top-to-bottom instead of vanishing into callback tunnels.

# The Journey

## War Story: Placeholder Expense Creation

Inside `MainAuraView`, there was a button constructing an `Expense` with an empty name and an editor placeholder for `Decimal`. That is the software equivalent of leaving a sticky note that says "real code goes here." The fix was intentionally small: generate a random human-readable expense name, generate a currency-like `Decimal`, and insert the created model into `modelContext` so the button performs an actual action instead of creating a temporary object and immediately forgetting it.

Lesson learned: if a debug or seed-data control exists in the shell, make it complete enough to behave like real app code. Half-finished sample actions tend to calcify into mysterious landmines.

## War Story: The Empty State Hydra

`P0-101D` exposed a classic product-shell problem: empty and error states had started reproducing like gremlins after midnight. The account switcher had one style, the newsfeed had another, the music library had a third, and provider failures were one bad refresh away from wiping the whole mood of the screen. That is how apps end up feeling stitched together from unrelated prototypes.

The fix was to introduce a shared shell status language in `Auralis/Auralis/Aura/ShellStatusView.swift`. Think of it like finally giving the hotel front desk a script instead of letting every employee improvise. First-run guidance, provider failure, no-receipts, and empty-library states now come from the same family of views, and the newsfeed gained a compact failure banner so cached content can stay on screen while refreshes fail in the background.

The useful lesson: not every error should become a full-screen eviction notice. If the user still has good cached content, show the bruise, not the funeral. A small banner saying "we're showing your last sync" is far less destructive than tearing down the whole surface just because the network sneezed.

## War Story: The ENS Mirage

`P0-202` turned up a subtler trap: the UI said "address or ENS name," but the actual account-entry contract was fuzzy. The store would happily fish an address out of surrounding text, the QR flow accepted whatever stumbled into `activateWatchAccount`, and the product language implied ENS support before the ENS ticket existed. That is how state bugs get invited in wearing a helpful smile.

The fix was to make account entry boring in the best possible way. `AccountStore` now performs strict address validation for account-entry normalization: trim whitespace, accept canonical `0x...` or 40 hex characters without the prefix, lowercase the result, and reject everything else. Most importantly, `.eth` names are now rejected explicitly in this phase instead of being left in a Schrödinger state where the UI says yes and the architecture says "maybe later."

This is one of those moments where good product behavior comes from saying "no" clearly. A sharp rejection is better than a soft lie. If ENS resolution belongs to `P0-203`, then `P0-202` should not pretend otherwise.

# Engineer's Wisdom

Good engineers keep demo paths honest. If a button says it creates data, it should create valid data, use the real model path, and avoid editor placeholders that compile only in imagination. Small correctness fixes like that prevent the weirdest future bugs, because test scaffolding has a habit of becoming production-adjacent faster than anyone expects.

Another recurring pattern from this project: shared UI states are architecture, not decoration. A consistent empty or error pattern does more than look tidy. It keeps future tickets from inventing bespoke behavior, reduces contradictory messaging, and makes edge cases like cached-content fallback much easier to reason about. Senior engineers tend to spot that earlier and invest in the seam before the app grows three more surfaces.

The same goes for validation. Normalize at the boundary, not halfway through a persistence flow. If user input is supposed to represent an EVM address, capture that contract in one place and make every entry path play by it. "Helpful" permissiveness is usually just delayed ambiguity.

# If I Were Starting Over...

I would move `Expense` out of `AuralisApp.swift` into a dedicated model file before it grows teeth. Right now it works, but keeping app-entry code and data models in the same room is how "temporary" structure turns into permanent clutter.

I would also establish the shell-state pattern library earlier. Once a product has gateway, tabs, data fetches, and offline-ish behavior, empty and failure states stop being polish work and start becoming core navigation language. Waiting too long means spending extra time undoing a dozen slightly different "nothing here" cards later.

I would also split "address parsing" from "address extraction" earlier. Those are cousins, not twins. Parsing a user-entered account field should be strict. Extracting an address from a deep link or some wrapped payload can be more permissive. Mixing those jobs in the same helper is how you end up accidentally accepting inputs you never meant to support.

## War Story: The Planning Map Started Lying

There is a special kind of project drift where the code moves faster than the planning docs, and then the planning docs start gaslighting the next engineer. That happened here. The implementation-order plan correctly treated `P0-101B`, `P0-101D`, `P0-202`, and `P0-601` as complete, and the current project state also says `P0-204` is done. Meanwhile, some ticket-specific notes still insisted `P0-601` and `P0-204` were blocked. That is how a team loses a day to arguing with yesterday's paperwork.

The fix was not glamorous, but it was necessary: promote the implementation-order plan back to the source of truth, mark `P0-204` as completed there, and move the recommended next sprint to `P0-401` -> `P0-301` -> `P0-701A` instead of pretending we still need to build the shell baseline. Think of it like updating the trail markers after the bridge has already been built. If the sign still says "river impassable," people will keep packing boats for no reason.

The lesson is painfully reusable: dependency docs are architecture tools, not souvenirs. Once they stop matching reality, they start generating fake blockers. When a ticket moves from "blocked" to "done," the planning artifacts need the same state transition the code just went through.

## War Story: The Chrome Inspector Broke The Build

This one was classic shell drift. The chrome inspector in `GlobalChromeView` was already trying to read `accountDisplay`, `chainDisplay`, and `freshnessLabel` from `AppContext`, but `AppContext` itself still looked like an earlier draft. It stored `chain` and `mode` as `String`, then got fed a real `Chain` and `AppMode`, and it never grew the computed display properties the inspector expected. The result was the software equivalent of a hotel front desk printing badges for guests who do not exist yet: instant compiler revolt.

The right fix was small and local. Instead of pushing more conversion glue into the view, `AppContext` was upgraded to be the thing the chrome thought it already was. The snapshot layer now stores `chain.rawValue` and `mode.rawValue`, and `AppContext` itself exposes the display helpers for account, chain, and freshness. Once that happened, the build went green again.

The lesson is simple: view models and context snapshots are contracts, not buckets. If a view consumes a shaped UI-facing model, keep that shaping in the model layer. Otherwise every screen starts growing its own tiny adapter logic, and eventually one of them forgets a field and takes the build down with it.
