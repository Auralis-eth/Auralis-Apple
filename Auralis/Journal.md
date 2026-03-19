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

# Engineer's Wisdom

Good engineers keep demo paths honest. If a button says it creates data, it should create valid data, use the real model path, and avoid editor placeholders that compile only in imagination. Small correctness fixes like that prevent the weirdest future bugs, because test scaffolding has a habit of becoming production-adjacent faster than anyone expects.

Another recurring pattern from this project: shared UI states are architecture, not decoration. A consistent empty or error pattern does more than look tidy. It keeps future tickets from inventing bespoke behavior, reduces contradictory messaging, and makes edge cases like cached-content fallback much easier to reason about. Senior engineers tend to spot that earlier and invest in the seam before the app grows three more surfaces.

# If I Were Starting Over...

I would move `Expense` out of `AuralisApp.swift` into a dedicated model file before it grows teeth. Right now it works, but keeping app-entry code and data models in the same room is how "temporary" structure turns into permanent clutter.

I would also establish the shell-state pattern library earlier. Once a product has gateway, tabs, data fetches, and offline-ish behavior, empty and failure states stop being polish work and start becoming core navigation language. Waiting too long means spending extra time undoing a dozen slightly different "nothing here" cards later.
