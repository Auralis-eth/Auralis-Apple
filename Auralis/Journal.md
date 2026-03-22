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

## War Story: Receipts Were A Ghost Route

The shell talked about receipts like they were already part of the building, but they were really more like a name on an empty office door. The deep-link parser could recognize receipt links, yet `MainAuraView` immediately turned around and said receipt routing was unsupported. At the same time, root navigation had no Receipts surface at all. That is the kind of half-wired feature that makes planning docs sound more complete than the product actually is.

The fix for the first remediation slice was intentionally narrow: give receipts a real home in the root shell and stop pretending the route is unsupported. `MainTabView` now has a Receipts tab, the router can navigate to receipt detail, and the shell routes receipt deep links into a placeholder receipts surface instead of throwing an error. It is not the full `P0-503` timeline yet, but it is at least a real hallway instead of a painted-on door.

The lesson here is that route support is binary in product terms. If a parser accepts a destination, the shell needs a real place to send the user. Anything else is just a deferred crash in nicer clothes.

## War Story: The Receipt Schema Was Pretending To Be Broader Than It Was

The receipt system had a familiar Phase 0 smell: the docs described a broad audit trail, but the actual stored model was still carrying a much thinner backpack. In practice, receipts had `category`, `kind`, a correlation ID, and a payload. Useful, yes. But if you claim the schema includes actor, mode, trigger, scope, summary, provenance, and success or failure as real fields, then hiding half of that inside arbitrary payload keys is just paperwork cosplay.

The fix was to make the contract honest. `ReceiptDraft`, `ReceiptRecord`, and `StoredReceipt` now carry those fields explicitly, while compatibility aliases keep older call sites from exploding all at once. The account and networking recorder seams were then upgraded to populate those fields on purpose instead of relying on old `category` and `kind` shorthand plus payload folklore.

The important lesson is that schemas are promises. If a field matters to downstream filtering, export, or reasoning, it should exist as a field. Once teams start saying "well technically it’s in the payload," they are usually one sprint away from rebuilding the same meaning three different ways.

## War Story: Default Arguments Are Sneaky In Actor-Isolated Code

The Swift 6 concurrency cleanup looked simple at first: `SwiftDataReceiptStore` is main-actor-bound because it touches `ModelContext`, and `ReceiptBackedAccountEventRecorder` is main-actor-bound because it writes through that store. So the obvious move was to put the protocols on `@MainActor` too. That part was correct. Then Swift helpfully pointed out the less obvious trap: `AccountStore` had a default argument `NoOpAccountEventRecorder()`, and default arguments are evaluated from a nonisolated context. Translation: a tiny convenience initializer had quietly become a concurrency landmine.

The fix was to stop being cute with the default parameter. `AccountStore` now has an overload that explicitly injects the no-op recorder from within the actor-isolated initializer path, which keeps the concurrency contract honest and avoids weakening the actor boundary just to preserve a shorthand.

The lesson is worth remembering because it shows up all over Swift 6 migration work: the real problem is often not the actor annotation itself. It is the little convenience feature sitting next to it that was written before isolation rules got teeth. Default parameters, static helpers, and “harmless” protocol boundaries are where a lot of migration friction actually hides.

## War Story: Observe Mode Was A Badge Without Teeth

For a while, Observe mode looked more official than it really was. The chrome badge said "Observe," which was nice branding, but the underlying `ModeState` still exposed a public mutation seam and the policy gate logic mostly existed as an idea waiting for a future ticket. That is the software version of putting up a "No Entry" sign on a door you forgot to lock.

The fix for the remediation pass was to make the contract real. `ModeState` is now hard-locked to `.observe` in Phase 0, the public mutation path is gone, and `ExecutePolicyGate` now produces a concrete denial result that also writes a receipt with explicit policy metadata. To keep this from becoming another invisible seam, the shell also gained a small Observe-mode policy demo surface so blocked actions can be exercised through real UI and not just through hopeful comments. A focused test now confirms that denied actions log the expected receipt.

The lesson is that policy state should behave like a circuit breaker, not a sticker. If the UI says the app is in a constrained mode, the code needs to enforce that constraint at the action boundary and leave an audit trail when it does. Otherwise "mode" is just typography cosplaying as architecture.

## War Story: The Active Chain Lived In Two Places And Only One Of Them Was On Screen

The chain-scope bug was a classic split-brain problem. `EOAccount` already persisted a `currentChain`, which made it look like chain scope was per-account. But the shell also kept its own `@State currentChain`, and that was the value the chrome, gas surface, news flow, and token views were actually reading. The account switcher updated the persisted model, saved it, and then quietly walked away. The UI kept showing the old chain like nothing had happened. That is the architecture equivalent of updating the hotel reservation system but forgetting to tell the front desk.

The fix was to choose a real authority chain and wire the seams to respect it. When an account is restored or selected, the shell now adopts that account's persisted `currentChain` instead of blindly trusting the old app-wide `currentChainId`. When the active chain changes in the switcher, it now updates the live shell binding immediately. And when the shell's `currentChain` changes for any reason, it writes that value back into the active account record so persistence and UI stay in lockstep.

The lesson is that duplicated state is not automatically evil, but it is always guilty until proven coordinated. If one copy drives rendering and the other copy drives persistence, you need an explicit synchronization contract or the app will eventually start arguing with itself. In this case, the safest contract is simple: the selected account owns the chain scope, and the shell is the live projection of that choice.

## War Story: Chain Scope Was Changing Quietly Enough To Look Broken

After the Task 5 state unification, the visible chain finally updated when someone changed it. Better, but still not good enough. The change was happening almost like a whisper: SwiftData got a new value, the UI reacted, but there was no receipt proving it happened and no rebuild hook telling the rest of the app to refresh the scoped data. That kind of half-fix is dangerous because it makes the product look alive while the audit trail still sees nothing.

The remediation was to make chain changes behave like real system events. The account receipt seam now has explicit events for preferred-chain and current-chain changes, and the account switcher runs those through a small planner that asks one boring but critical question first: did the chain actually change? If the answer is no, nothing gets written, nothing gets refreshed, and no duplicate loop gets a chance to start. If the answer is yes, the preferred-chain path records a receipt and persists the change, while the current-chain path does that and also triggers a single refresh callback for the active scope.

The lesson here is that state changes with product meaning deserve three things: persistence, observability, and side-effect discipline. If you skip the first, the state disappears. If you skip the second, the system becomes unauditable. If you skip the third, every picker turns into a bug generator. Good engineering is often just refusing to accept any two out of three.

## War Story: The Address Contract Needed A Verdict, Not More Ambiguity

`P0-202` had reached that awkward stage where the code and the original ticket language were politely disagreeing in public. The implementation already normalized everything to lowercase canonical `0x...` form, which is great for persistence, duplicate detection, and deterministic comparisons. But the older acceptance wording still sounded like EIP-55 checksum display might be required. That is how teams end up wasting time debating whether a mismatch is a bug or just an outdated promise.

The right move here was to stop hedging and pick a contract. Phase 0 now explicitly stores and copies lowercase canonical addresses, and the auth entry UI shows that exact normalized value when the input is valid so the user can copy what the app will actually persist. No checksum theater, no half-implemented display rule, and no pretending ENS belongs in this phase. Checksum display can come back later if a future ticket truly needs it, but it should arrive as a deliberate product decision, not as a surprise side effect.

The lesson is that normalization rules are product rules. They affect persistence, deduping, copy behavior, and what users trust as the "real" value. Once a system has already converged on one practical contract, good engineering is often about writing that contract down clearly and exposing it in the UI, not reopening the debate because an older sentence sounded more ambitious.

## War Story: The Chrome Ticket Was Done, But The Context Ticket Was Trying To Hitchhike

By the time the remediation work reached the chrome audit, `P0-101B` and `P0-101C` were starting to blur together in the paperwork. The shell clearly had a real chrome now: account switcher, Observe badge, freshness, search, and context entry all lived at the shell layer and followed the user across the main surfaces. But the context-inspector ticket wanted more than a doorway. It wanted the actual room behind the door: provenance, last fetch receipt linkage, stale handling, and refresh behavior tied to the future context stack.

The fix here was mostly intellectual honesty. `P0-101B` was re-validated as complete because the chrome itself is doing its Phase 0 job now. `P0-101C` stayed blocked because the current inspector is still a summary sheet, not the full context behavior promised by that ticket. In other words: the front desk is built, the sign for the back office exists, but the back office is not staffed yet.

The lesson is that neighboring tickets often try to merge when an interface seam starts to look polished. Good engineering means resisting that drift. A visible entry point is not the same thing as a completed workflow. If you mark both done just because the UI looks tidy, you turn the next dependency ticket into a scavenger hunt.

## War Story: "Complete" Was Doing Too Much Work

This pass was less about writing app code and more about interrogating the paperwork with a flashlight. Several Phase 0 tickets had already been marked complete in strategy docs or the implementation-order plan, and some of them really were done. But a few others were "complete" in the way a moving box is labeled "Kitchen" even though someone stuffed a phone charger and a screwdriver in there too. Close enough for transport, not close enough for truth.

The practical fix was to write two new control documents at the project root: `P0-Remediation-Checklist.md` and `P0-Remediation-Tasks.md`. The checklist is the blunt instrument. It says, ticket by ticket, what is actually complete, what is only complete under a narrowed scope note, and what still needs code. The task list is the wrench set next to it: concrete implementation tasks, likely file touch points, and validation expectations. Just as important, the checklist also records document gaps, like the missing dedicated `P0-101A` repo doc, because missing planning docs are how oral tradition sneaks into architecture.

The lesson is simple and annoyingly universal: "complete" is not a feeling. It is an agreement between code, tests, and docs. When any one of those three wanders off, the team starts paying interest on ambiguity.

## War Story: The Shell Status Views Were Secretly The Primitives

`P0-101E` had one of those sneaky gaps where the app looked more reusable than it really was. The shell already had decent empty and error patterns in `ShellStatusView.swift`, so at a glance it felt like the design-system work was basically done. But that was a bit like saying a restaurant has a public menu because the chef keeps the recipes in his apron pocket. The patterns existed, but they were trapped inside shell-specific wrappers instead of being first-class Aura primitives that other surfaces could use directly.

The fix was to promote the shared shapes into real primitives: `AuraEmptyState` and `AuraErrorBanner`. Then the shell wrappers were rebuilt on top of those primitives, and the newsfeed was switched to consume them directly for its empty and error states. That matters because it changes the relationship between the shell and the rest of the product. The shell is no longer the only place that knows how to render those patterns; it is just one client of the shared Aura language.

The lesson is that reusable UI is not defined by visual similarity alone. A pattern becomes a primitive when other features can actually reach for it without importing half the shell as emotional support.

## War Story: The Context Ticket Was Blocked On Paper, But Already Knocking On The Door In Code

`P0-401` had turned into a classic planning contradiction. One set of docs said it was the next ticket to start right after chain scope landed. Another set still treated it like a full stop because `P0-302` had not delivered proper freshness primitives yet. Meanwhile, the codebase had already started growing a tiny unofficial context seam in `AppContext.swift`, and the chrome inspector was quietly living off that seam like a pop-up shop operating before the building permit arrived.

The fix was to stop pretending the choice was binary. We promoted the seam into a real `ContextSnapshot` contract with a schema version, typed scope, provenance-bearing fields, library pointers, local preferences, and freshness metadata. That gave the project an honest source of truth for "what context means" without faking provider-backed balances or TTL logic that does not exist yet. The old `AppContext` stayed around as a compatibility adapter, which is the software equivalent of changing the plumbing behind the wall without making the tenants shower in the yard.

The lesson is that some dependencies block completion, not progress. If you wait for every upstream system before naming your own data contract, architecture stays mushy and every downstream UI invents its own version of the truth. But if you invent fake data just to look unblocked, you create scaffolding that future work has to demolish. Senior-engineer thinking lives in that narrow middle lane: formalize the contract now, leave the missing parts visibly empty, and write the docs so nobody confuses "startable" with "finished."

## War Story: The Provider Layer Was Hiding In Plain Sight As Constructor Calls

`P0-301` looked abstract in the ticket, but the actual problem in code was concrete and slightly embarrassing: the app already had providers, they were just wearing fake mustaches. `NFTFetcher` was constructing `AlchemyNFTService` directly inside its fetch loop, and the gas view model was instantiating `Infura` like it was ordering takeout. That works until you want to swap providers, centralize RPC configuration, or explain with a straight face that UI does not talk straight to lower-level network clients.

The fix was to stop treating configuration as string trivia sprinkled through the codebase. A centralized provider configuration resolver now builds the chain-aware Alchemy and Infura endpoints in one place. NFT inventory fetching moved behind an injected provider factory, gas pricing moved behind a protocol, and native balance support was added as a real provider capability even though no shell surface consumes it yet. That last part matters because it gives the architecture somewhere honest to stand when account summary and token work show up later.

The lesson is that dependency injection is not about turning every type into a theology debate. It is about making the code admit who it depends on. Once a network client is born inside a feature method, it stops being a provider and starts being a secret. Good engineering drags those secrets into the daylight early, while the seams are still cheap to change.

## War Story: Structural Scaffolding Is What Stops The Shell From Growing Tentacles

`P0-701A` is the kind of ticket teams love to postpone because the app still "works" without it. The shell was rendering, routes were moving, receipts were being written, and Observe-mode denials were even showing alerts. The trouble was where those behaviors lived. The tab view was creating its own mode owner, building context sources directly, and reaching down to `SwiftDataReceiptStore` when it needed policy denial logging. That is not architecture, that is a very polite tangle.

The fix was not to carve the app into fake modules overnight. It was to introduce a small live service hub that the shell can depend on without knowing every concrete implementation underneath it. `MainAuraView` now owns the shared mode state at the root, the shell builds context through a context-source builder, receipt-backed flows share a common receipt-store factory seam, and the policy-denial UI talks to a policy action service instead of constructing storage itself. In restaurant terms, we did not rebuild the whole kitchen. We labeled the stations, put the knives where they belong, and stopped letting the dining room borrow the oven mitts.

The lesson is that scaffolding is about making the next good decision easier than the next bad one. `P0-701A` does not "solve boundaries." It creates the first honest paths through them, so future tickets have somewhere clean to plug in instead of drilling new holes through the wall.

## War Story: Correlation IDs Were Falling Off The Conveyor Belt

`P0-502` exposed a classic orchestration bug disguised as "mostly working" receipts. Account add, select, remove, and chain-scope change events were already writing receipts, which sounds healthy until you ask the obvious follow-up question: which receipts belong to the same user action? The answer was basically "good luck, detective." A manual account activation wrote an add receipt and then a select receipt, but nothing tied those two facts together. Current-chain changes were even sneakier: the account-scope change receipt and the follow-on NFT refresh receipts were born in the same user interaction, then immediately lost each other in the crowd.

The fix was intentionally narrow. Instead of inventing a global logger or shoving correlation logic into SwiftData, the existing account event seam learned how to accept an optional caller-provided correlation ID. `AccountStore` now threads that ID through chained operations like activate, select, and remove, and the account-switcher UI generates one correlation ID for a current-chain change and reuses it for both the chain-scope receipt and the triggered NFT refresh. Same event family, same receipt breadcrumb.

The lesson is that correlation IDs are not garnish. They are the claim ticket you get at coat check. Without them, you still technically own a coat, but retrieving the right one becomes a social experiment. Good orchestration code creates the claim ticket at the boundary where the user action starts and keeps handing it forward until the flow is actually done.

## War Story: Freshness Was Mostly A Vibe Until We Gave It A TTL

`P0-302` was the moment the app had to stop saying "freshness" with a straight face while really meaning "there is a date somewhere and we hope nobody asks follow-up questions." `NFTService` already remembered `lastSuccessfulRefreshAt`, and the context snapshot already had a freshness section, but the actual rules were squishy. Stale evaluation was ad hoc, future timestamps could make the math weird after clock shifts, duplicate refresh taps could pile into the same fetch path, and failed refreshes were accidentally wiping the visible error state right after recording it. That is not freshness; that is a polite shrug in a trench coat.

The fix stayed narrow on purpose. We did not build a grand cache empire. Instead, the active NFT refresh path got a real TTL-backed freshness contract. `ContextFreshness` now knows its TTL and can evaluate staleness safely with age clamped at zero so a clock jump into the future does not produce nonsense. `NFTService` now coalesces duplicate in-flight refreshes for the same account and chain instead of letting two callers race to ask the same question twice. Just as important, when a refresh fails after a previous success, the service keeps the last successful timestamp and the visible error state, which means the app can honestly say "showing last sync" without amnesia.

The lesson is that cache freshness is not a decorative label. It is an agreement about time, failure, and trust. If the app tells the user data is fresh or stale, that statement needs a rule behind it, not a guess. Senior-engineer thinking here is all about keeping the rule small, explicit, and close to the orchestration seam that actually owns the fetch lifecycle.

## War Story: The UI Was Technically Reading Context, But It Was Bypassing The Front Desk

`P0-402` was one of those architecture tickets where the app looked respectable from ten feet away and suspicious from two. The shell already had a `ContextSnapshot`, and the inspector already showed context values, but `MainTabView` was still reaching directly for `ContextSource` like a customer walking past the host stand and into the kitchen. That works until you need caching, coalescing, request isolation, or any future provider orchestration. Then suddenly the "simple" direct call path becomes the reason every downstream ticket wants its own private shortcut.

The fix was to install a real `ContextService` seam and make the UI use it as the only entry point. The service owns the cached snapshot for the active shell slice, refreshes it from captured scope inputs, coalesces duplicate in-flight requests for the same account and chain, and refuses to let an older request overwrite a newer scope after a rapid account switch. In restaurant terms, the inspector and shell now order through the expediter instead of yelling straight at the line cooks.

The lesson is that service boundaries are not busywork when they sit on top of mutable scope. They are the thing that keeps "current account" and "current chain" from turning into a race-condition improv show. Good engineers put the front desk in front of the kitchen before the lunch rush starts, not after three tickets have already been plated for the wrong table.

## War Story: Raw Errors Make Terrible Product Policy

`P0-303` was the moment the app had to admit that `Error?` is not a UX strategy. Before this pass, the newsfeed mostly asked a yes-or-no question: "is there an error?" If yes, it either threw up a full-screen provider failure card or slapped the raw localized string into a warning banner. That works right up until you care whether the problem is offline mode, provider rate limiting, malformed provider data, a bad wallet scope, or a configuration mistake in the build itself. At that point a naked error string is like asking the hotel concierge to explain every city emergency by reading directly from the fire alarm panel.

The fix was to add a typed `NFTProviderFailure` seam in the refresh layer and let the shell consume that contract instead of interrogating raw `Error` values. Now the app can classify failures into useful buckets like offline, rate-limited, invalid response, invalid scope, misconfigured, busy, and generally unavailable. From there, the UI gets a clean choice between blocking mode and degraded mode. No cached content? Show a real provider failure card. Cached content still on screen? Show the gentler "last sync" language and keep the gallery navigable instead of acting like the floor disappeared.

This also tightened up receipts. Failure receipts no longer just stash a stringified error and call it a day. They now carry structured fields like `errorKind` and retryability, which means future debugging is less archaeology and more accounting. The lesson is simple: raw errors are useful evidence, but terrible policy. Good engineers translate them once at the orchestration seam, then let the rest of the app reason about stable categories instead of improvising every time the network gets moody.
