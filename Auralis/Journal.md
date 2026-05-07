# Journal

## The Big Picture

Auralis is what happens when an NFT wallet explorer, a polished dashboard, and a music player decide to share an apartment instead of living in separate apps. You connect an address, the app pulls in wallet context and NFT inventory, then turns that data into several product surfaces: home, newsfeed, gas tools, token views, receipts, and music playback.

The important part is that this is not a “show a list and call it a day” app. It has a real shell, real persistence, real routing, and a long-lived audio engine. It behaves more like a small operating system for an NFT-centric account than a toy demo.

## Architecture Deep Dive

Think of the app like a boutique hotel:

- `MainAuraView` is the front desk. It decides whether you are checking in, waiting for your room, or already headed upstairs.
- `AppRouter` is the concierge. It knows where each tab can take you and keeps the navigation mess from spilling all over the lobby.
- `NFTService` is housekeeping plus logistics. It fetches inventory, cleans stale data, and keeps SwiftData in sync.
- SwiftData is the storage room. It remembers what the network already told us so the app does not behave like it has goldfish memory.
- `AudioEngine` is the resident DJ booth. It stays alive across the app and keeps playback state coherent while views come and go.
- The home presentation logic is the lighting designer. It takes account state, pinned actions, and chain context and turns them into the polished Aura home experience.

The recurring pattern is deliberate ownership. The shell owns long-lived services, feature views receive focused inputs, and logic objects do presentation shaping instead of bloating every SwiftUI view with conditionals and formatting code.

## The Codebase Map

- `Auralis/Aura/`
  The main product shell and UI surfaces.
- `Auralis/Accounts/`
  Account persistence and wallet-facing mutations.
- `Auralis/Networking/`
  Provider abstractions, NFT fetches, ENS support, and token/gas plumbing.
- `Auralis/DataModels/`
  Shared persisted/domain models. Also, occasionally, a file that forgot what its job was.
- `Auralis/MusicApp/AI/`
  The active music experience and audio engine path.
- `Auralis/Receipts/`
  Audit-style event and receipt timeline views.
- `AuralisTests/`
  Contracts, state logic, and feature behavior checks.

If you are navigating this repo for the first time, start at `MainAuraView`, then `MainTabView`, then whichever feature surface you care about. That path gives you the real call graph instead of archaeological artifacts.

## Tech Stack & Why

- SwiftUI
  Because the app is heavily state-driven and has many presentation surfaces that benefit from declarative composition.
- SwiftData
  Because local persistence matters here, and the app wants models close to SwiftUI instead of a hand-rolled persistence layer for every feature.
- Swift Concurrency
  Because networking, refresh flows, and audio coordination are easier to reason about with structured async work than callback spaghetti.
- AVFoundation
  Because eventually somebody has to actually play the music instead of just admiring the cover art.
- Routing and presentation helpers
  Because once a shell grows past a couple tabs, ad hoc navigation state turns into a junk drawer fast.

## The Journey

- Package extraction pass: `EOAccount`, `NFT`, `Chain`, and their persistence-side traveling companions moved into `AuralisPrimaryModels`, but the interesting part was not the file shuffle. The real lesson was that `NFT` had been quietly towing a parade float: `Tag`, `Playlist`, nested SwiftData models, and media/JSON helpers all had to cross the module border too. The fix in the app target was deliberately boring and therefore good: app-side typealiases now point at the package models, which avoids a “touch fifty imports and pray” migration while keeping the package as the new source of truth. One seam stayed local on purpose: `Chain.web3EthereumNetwork` remains in the app as an extension so the package does not inherit an unnecessary `web3` dependency just to compute one adapter value.

- War story: the "old music player" was not one old view. It was a whole backstage crew still sneaking onstage through the Music tab fallback, the shell mini player, the now-playing sheet, and detail routes that still pushed `AI/V1` views even when AuraPlay owned the tab. The cleanup fix was to move the still-shipping player surfaces into `MusicApp/AuraPlay/`, delete the legacy fallback switch, and make failure honest: if AuraPlay storage or audio boot fails, Music now shows an explicit unavailable state with retry guidance instead of quietly slipping users back into the retired app.
- The lesson was memorable and mildly rude, which usually means it is true: a "migration seam" stops being a seam the minute production users can still walk through it every day. At that point it is just a side door for technical debt wearing a visitor badge.
- War story: the `NFTService` refactor split persistence and cleanup into separate seams, but three unit-test files were still speaking the old dialect. The failures looked noisy at first, but the root cause was simple contract drift: tests were still passing `shouldCleanupStaleInventory` into `persist`, and the `NFTService` test doubles no longer satisfied `PersistNFTInventoryUsing`. Fix was to update the tests to call `cleanupStaleInventory(...)` explicitly where needed and teach the stubs the new protocol shape.
- Another small trap: SwiftLint was configured tightly enough that `try! #require(...)` inside tests failed the build. Swapping those to `try #require(...)` and marking the test functions `throws` kept the assertions just as clear without leaving force-try landmines in the target.

### NFTService: Stop Making One Type Run the Entire Warehouse

This architecture ticket is the repo finally admitting that `NFTService` had become the project’s overachieving warehouse manager, forklift driver, inventory clerk, janitor, and night supervisor all at once.

- The file already contained a strong clue about the right future shape: it had a real persistence actor boundary and a real metadata-preparation pipeline, but both were still living inside the same giant service. That is like discovering your “single room” apartment already has kitchen walls drawn in pencil. The plan for `ARCH-002` is basically tracing those walls in ink.
- The important decision was to split by responsibility, not by vibe. Fetching becomes `FetchNFTInventoryUseCase`. Metadata enrichment becomes `PrepareNFTMetadataUseCase`. SwiftData writes and stale cleanup become `PersistNFTInventoryUseCase`. Freshness math gets its own `NFTRefreshStateComputer`. The remaining `NFTService` is then just the conductor waving the baton instead of also trying to play drums, violin, and bass simultaneously.
- We also chose a pragmatic migration path instead of a naming revolution on day one. Keep the shell-facing public type as `NFTService` initially, extract the real seams, prove the orchestration shape, and only then decide whether the final honest name should be `NFTRefreshCoordinator`. Good refactors separate structural change from rename turbulence whenever possible.

The lesson is one senior engineers keep relearning in different costumes: when one type owns fetch logic, transformation, persistence, cleanup, and UI freshness state, every bug starts as a group project. The best fix is not “write more comments.” The best fix is giving each concern its own room and making the coordinator earn its title by coordinating.

The implementation pass for `ARCH-002` finally made that architectural speech real instead of aspirational:

- `NFTService` is now the thin coordinator it claimed to be in meetings. It still owns phase publishing, in-flight cancellation, refresh-event wiring, and the shell-facing API, but the heavy lifting moved out into `LiveFetchNFTInventoryUseCase`, `LivePrepareNFTMetadataUseCase`, `LivePersistNFTInventoryUseCase`, and `NFTRefreshStateComputer`.
- The fetch seam now owns the awkward “did we finish the whole inventory or just a page-shaped slice of it?” decision. That matters because stale cleanup is only safe after a real full refresh. Before this split, that knowledge leaked straight into the coordinator.
- The metadata pass stopped being a pile of private helper functions hiding in a service trench coat. Base64 token-URI decode, raw metadata fallback, refresh-scope application, and deduplication now live together in one place, which is where future bugs will be much easier to pin down.
- The SwiftData write path is now its own room with the same furniture as before: the `@ModelActor` boundary survived, merge behavior still preserves local-only state like tags, stale cleanup still stays conditional, and orphaned shared models still get pruned instead of haunting the store forever.
- We also wrote the missing seam-level tests the old structure made awkward. There are now focused suites for fetch completion semantics, metadata preparation, persistence behavior, refresh-state bookkeeping, and coordinator sequencing/cancellation behavior. In other words, the tests no longer need to treat one giant service like a black-box vending machine and hope the right snack falls out.

The memorable lesson from the implementation itself: good refactors are a lot like moving a busy restaurant kitchen from one room to four connected stations. If the tickets still get out on time and nobody drops a pan, the diners just see dinner. The staff, meanwhile, finally stops bumping elbows every time one person reaches for the salt.

The first post-split bug was a perfect little architecture trap. The extracted persistence actor was rebuilding multiple fresh `NFT` graphs, each with its own brand-new `Contract` and `Collection`, and only afterward trying to canonicalize those relationships back into shared instances. SwiftData was not amused. The result was a ghost-story grade failure where save validation complained about blank `Contract` and `Collection` records with missing required fields, even though the source data looked fine.

- The fix was not “convince SwiftData harder.” The fix was to stop constructing the wrong graph in the first place.
- `PersistNFTInventoryUseCase` now resolves shared `Contract` and `Collection` models before building each `NFT`, so every new record starts life pointing at the final canonical relationship objects instead of temporary lookalikes.
- We also replaced a lazy temporary-model trick for computing scoped IDs with plain helper functions. Same result, less weirdness inside the persistence actor.
- There was a second, sneakier extraction bug hiding one layer up: bundling persistence and stale cleanup into one use-case call made the coordinator lie about its phase. On full refreshes it could publish `.cleaningUp` before persistence had actually finished. The fix was to keep both behaviors owned by the persistence use case, but expose them as separate operations so `NFTService` can still sequence `persist -> cleanup -> success timestamp` honestly.

The lesson: if shared models are part of the storage contract, resolve them before you assemble the objects that depend on them. Retrofitting identity after graph construction is how you end up hunting phantom rows at midnight.

### ShellServiceHub: Stop Letting the Front Desk Crawl Into the Boiler Room

This architecture decision was the repo finally admitting that `ShellServiceHub` had become too convenient for its own good.

- On paper, the hub looked like a polite composition helper. In practice, it let presentation code reach into account factories, provider construction, receipt logging, search history, policy gates, and privacy reset wiring. That is less “dependency injection” and more “every room in the hotel has a skeleton key.”
- The fix is not to replace one giant bag with three medium-size bags wearing fake mustaches. The decision in `ARCH-001` is to keep use-case protocols at the feature boundary when a view is triggering work, while still allowing direct injection for narrow, stable stores that are mainly being rendered. That is the sweet spot between architecture rigor and protocol cosplay.
- We also chose not to bless `AppServices.swift` as the forever-home of composition. It can be the moving truck during the refactor, but not the new house. Once the migration lands, composition code should split into shell bootstrap dependencies, feature adapters, and live builders so the next engineer does not discover a second service locator growing in the walls.
- For previews and tests, the rule is similarly pragmatic: keep `preview` and `testValue` factories as extensions in preview/test support areas instead of baking them into the main production file. Same ergonomics, less production clutter.

The lesson is senior-engineering-simple: if a SwiftUI view can casually reach into infrastructure plumbing, that plumbing is eventually going to leak into product logic. The right boundary is not “views know nothing.” The right boundary is “views know only the contracts that make sense from where they stand.”

The follow-on lesson came when the planning doc itself needed cleanup. Architecture notes that still contain conversational “I agree with both” language are fine during discovery and bad for handoff. We turned the remaining lifetime question into an explicit ownership policy with a review test and a small dependency table. Much better. A handoff doc should read like a map, not like chat logs taped to the dashboard.

### Swift Testing Meets MainActor and Throws a Chair

This was a classic Swift 6 test-target failure where the app code was innocent and the tests were the ones walking into traffic.

- `ModeState` is correctly `@MainActor` because it owns UI-facing observable state and `@AppStorage` plumbing. `ModeReceiptAugmentor.attachMode(...)` is also `@MainActor` because it reads that same shared state.
- `ModeStateTests` was still written as a plain nonisolated suite, which used to feel harmless and now gets you a compiler lecture. The result was a test build that never reached execution because the suite was calling a main-actor initializer and reading a main-actor property from the wrong context.
- The fix was intentionally small: move the suite onto `@MainActor` instead of watering down the production annotations. That keeps the app contract honest and makes the tests state their threading expectations explicitly.

The memorable lesson: when Swift Testing starts vomiting macro noise and “nothing ran,” do not immediately blame the framework. Sometimes the test suite just forgot which actor owns the room.

### AuraPlay Phase 1: The Blueprint Matters Before the Bricks

This planning pass looked simple on paper: take the AuraPlay Phase 1 ticket list and turn it into work. The catch was that the ticket set describes a brand-new app with a brand-new identity, while the actual workspace is an established Auralis repository with its own history, architecture, and shipping concerns. In other words, the blueprint arrived for a clean lot, and the lot already has a house on it.

- The first important decision was to stop pretending that "single initial commit" or "empty intentional project" acceptance criteria could be literally true inside this repo. That is not pessimism; that is engineering honesty. A plan that ignores repository reality is just a future bug report wearing business clothes.
- The resulting strategy treats the repo boundary as the first architectural question, not an administrative afterthought. Should AuraPlay be a separate repo, a new target in this repo, or merely a conceptual retrofit of Auralis? That answer changes the meaning of nearly every P0 ticket.
- We also locked the sequence around the real choke point: architecture selection. DI, logging, test ergonomics, and service wiring all want to know whether the app is going TCA or native `@Observable` first. Trying to "just start the project" without that decision is how foundation work turns into a partial rewrite by ticket four.

The useful lesson is very senior-engineer flavored: before you write the first line of "implementation," make sure the physical reality of the repository matches the story the phase plan is telling. Otherwise you are not building a foundation. You are pouring concrete in somebody else's driveway.

That said, the product direction got sharper after the first draft: AuraPlay is not a separate app after all. It is the full rebuild of the existing Music tab inside Auralis, and it is allowed to share code with the rest of the app. That changes the plan substantially:

- the right move is not "bootstrap a new app," it is "create a clean module boundary for a music rebuild inside the current app"
- the architecture question is settled up front: native SwiftUI plus `@Observable`, no TCA detour, no framework beauty pageant
- the migration risk shifts from repo bootstrapping to ownership discipline, especially around the existing audio engine and the `MusicApp/AI/` surfaces that are already live

The better analogy is no longer "build a house on an empty lot." It is "renovate the nightclub without turning the music off mid-set." You keep the shared plumbing, electricity, and exits that already work, but you still need a disciplined plan for which room gets rebuilt first and which wires nobody is allowed to cut casually.

### AuraPlay Phase 2: Build the Storage Basement, Not a Second House

The next AuraPlay planning pass had a similar trap wearing a different outfit. Phase 2 is all about persistence, search, playlists, and playback state. That kind of ticket list tempts engineers into drawing a brand-new subsystem in a vacuum, as if the existing AuraPlay seams were just polite suggestions. They are not.

- Phase 1 already gave AuraPlay a front door: `AuraPlayTabRootView`, `AuraPlayCompositionRoot`, `AuraPlayDependencies`, and the first service seams for library, playback, queue, artwork, and logging. If Phase 2 ignores those and builds a parallel dependency story, the module ends up like a restaurant with two host stands and nobody sure which one seats the guests.
- The correct shape is deeper, not wider. SwiftData belongs underneath the current module boundary, not beside it. The shell still owns `EOAccount` and `Chain`, the tab seam still constructs live dependencies, and the new `@ModelActor` services become the backstage crew moving scenery while the actors stay on their marks.
- Search had its own shiny-object danger. A persistence phase plus search tickets is exactly how “maybe we should just drop in SQL/FTS” sneaks into a plan. This repo does not need another database religion. The Phase 2 strategy stays fully Apple-native: SwiftData for storage, a trie for instant prefix work, CoreSpotlight for system-grade text retrieval, and NaturalLanguage embeddings for the “show me dark ambient driving music” flavor of query.

The memorable lesson is architectural: when you add a basement to a house that people are already living in, the smart move is to support the existing structure while you dig. You do not build a second house three feet away and hope the kitchen figures it out later.

### AuraPlay Phase 2, Wave 1: Pour the Footings Before You Decorate the Room

The first implementation wave for AuraPlay Phase 2 was intentionally unglamorous, which is usually how you know it matters.

- We added the persistence spine before adding the real music entities. That meant `AppModelContainer`, `AuraPlaySchemaV1`, `AuraPlayMigrationPlan`, and `ADR-002` landed first. It is the software equivalent of agreeing where the pipes and breaker panel go before arguing about the backsplash.
- The key discipline was dependency shape. The only new shared persistence object is `ModelContainer`, threaded through `AuraPlayDependencies`. Not `ModelContext`, not a singleton, not a “temporary shortcut” that would still be here six months later wearing a fake name tag.
- We also updated the privacy manifest for app-container file metadata access. This is exactly the sort of compliance detail that gets ignored during architecture work because it feels less exciting than models and actors, and then later turns into an App Store paperwork ambush.

The useful lesson is simple: Wave 1 should make later waves easier to do correctly, not merely possible to start. A good foundation diff feels almost boring when you read it, and much less boring when it prevents the next four diffs from becoming archeological digs.

### AuraPlay Phase 2, Wave 2: Teach the New Basement to Hold Actual Records

Wave 2 is where the storage story stops being architectural fan fiction and starts holding real shapes.

- We added the first real AuraPlay persistence graph: `AuraPlayWallet`, `AuraPlayNFTToken`, and `AuraPlayMediaItem`. The important design move was making `MediaItem` the query-friendly front desk while `NFTToken` stays closer to the raw collectible identity behind the curtain.
- The import path also became real. `LiveAuraPlayLibrarySyncService` now reads wallet-scoped music NFTs from the existing app store and mirrors them into the separate AuraPlay SwiftData container. That is the “renovate the nightclub without shutting off the speakers” move in code form: the old system still knows where the records are, and the new system now gets its own organized crates instead of borrowing stacks forever.
- The library repository learned a practical migration trick instead of a philosophical one. If AuraPlay has already mirrored a wallet into its own store, reads come from the new persisted media graph. If not, the repository falls back to the legacy indexer. That is a clean handoff ramp, not a cliff.

The memorable lesson here is that migration work gets safer the moment you stop treating “old path” and “new path” like enemies. A good transition seam is more like a bilingual host than a coup.

### The App Contract Still Counts When the Feature Has Barely Started

This pass was configuration work, which means it was exactly the kind of work people postpone until App Review turns into a hostage situation.

- `Info.plist` already had background audio enabled, which is the glamorous part everybody remembers because it sounds like a feature. The missing pieces were the quieter contract items: a motion-usage string for the eventual run-detection story, wallet callback URL schemes, and the list of wallet apps we intend to probe with `canOpenURL`. That list matters because iOS treats undeclared probes like a bouncer treats fake IDs.
- The deep-link setup had an extra wrinkle: the codebase already speaks `auralis://` internally for app routing tests, while the wallet-pairing requirement wanted `auraplay://`. Instead of forcing those two worlds to duel at dawn, the bundle now declares both schemes. Product routing keeps its current language, and wallet callbacks get the scheme they asked for.
- The CarPlay entitlement was the other silent footgun. An empty entitlements file looks harmless right up until device builds or future capabilities expect a real key and find a blank stare instead. We added the audio entitlement now so later CarPlay work starts from an honest target contract instead of a paper shell.
- There was also no seam for testing `canOpenURL` behavior without dragging `UIApplication.shared` directly into unit tests. The fix was a tiny protocol-backed probe type. Nothing fancy, just enough abstraction to let a mock app answer “yes, MetaMask is installed” or “no, Ledger Live is not” without turning a simple availability check into global-state theater.

The lesson is boring and very real: product capabilities live partly in code and partly in the bundle contract around the code. If those drift apart, the app can look fine in the simulator right up until the OS, device, or App Review reads the paperwork more carefully than we did.

### ENS Trust Boundaries and Corrupt Chain Data

This was a "the app is being polite while doing the wrong thing" class of bug, which is often nastier than an obvious crash.

- ENS wallet entry had a trust leak. If the live ENS provider failed, the resolver could fall back to a stale cached mapping, and the address entry flow would happily save and activate that cached address as if it had just been verified. That is like asking a receptionist to confirm your hotel room number and getting "the Wi‑Fi is down, so I guessed from last week." The fix was to require a fresh ENS verification before saving an ENS-based account and to tell the user plainly when only cached data is available.
- Persisted chain raw values also needed a reality check. A few model accessors were quietly translating unknown local chain strings into `.ethMainnet`, which made bad data look valid and could route the app into the wrong scope. We moved that behavior from "silent fallback during reads" to "detect, log, and repair when accounts are loaded," and we stopped NFT refresh persistence from re-parsing stored chain raw values when the refresh scope already knows the correct chain.
- Shell restore got a matching cleanup. The selection persistence layer stored both wallet address and chain, but restore was only really trusting the account row. That made the saved scope feel more authoritative than it actually was. Restore now validates the persisted chain and reconciles it with the account’s repaired chain state instead of carrying dead or inconsistent selection data forward.
- ENS retry behavior also got less stubborn. Being offline is not a transient mystery that needs several dramatic retries before we admit reality. The ENS client now fails fast for deterministic offline conditions so cached fallback or user messaging can happen promptly instead of after a pointless backoff ritual.

The pattern worth remembering: graceful degradation is only graceful if the app also stays honest about what it knows, what it guessed, and what it could not verify.

### Storage and Networking Hardening: Fix the Leaks, Not Just the Symptoms

This pass was a tour of the kind of bugs that do not throw fireworks during a demo and still absolutely matter before shipping.

- The first bug was a SwiftData attic problem. `NFTService` was cleaning up stale `NFT` rows, but shared `NFT.Contract` and `NFT.Collection` models could still be left behind when refreshes deleted NFTs or repointed an existing NFT at a new contract/collection. Think of it like throwing away old mail while keeping every obsolete folder the mail used to live in. The fix was to prune orphaned shared models inside the persistence actor after both persistence and stale-record cleanup, so the storage graph stops accumulating little abandoned islands.
- ENS needed a reality check too. Most of the networking stack already had explicit timeout, retry, and typed-failure behavior. The web3-based ENS client was the odd cousin showing up without that discipline. We added a bounded retry loop and per-request timeout at the client boundary itself, which keeps resolver semantics, cache behavior, and receipt logging intact while making ENS transport behavior intentional instead of hopeful.
- User-facing provider errors got a cleanup pass in the places where backend prose was still sneaking through. Native balance status, ERC-20 holdings errors, and NFT provider failures now speak in app-owned language like “provider returned HTTP 500” or “provider reported an error for this wallet and chain” instead of parroting raw backend message text into the UI. Same facts, better contract.
- The ENS cache also stopped behaving like a haunted pantry. Previously, stale entries could sit in the persisted blob forever and merely wear a “stale” sticker when read. Now the cache store has an explicit retention window and prunes expired entries as part of normal cache access and writes. The nice part is that this keeps short-term stale fallback behavior, but it no longer lets old names pile up indefinitely.
- The last fix was less glamorous and very worth doing: a handful of main-thread persistence reads were answering tiny UI questions by loading entire tables first. That is fine when the app has ten records and less charming when it has ten thousand. Receipt counts now use scoped predicates, search history uses scoped sorted fetches instead of whole-table filtering, the music indexer filters for audio-bearing NFTs at the query boundary, and `MainTabView` stopped recounting NFTs from disk when the current account already carries the synchronized count it needs.

The broad lesson: ship-readiness is usually not about one giant crash. It is about removing slow drift, ambiguous contracts, and “probably fine” networking behavior before they turn into product folklore.

### Audit Triage: Fix the Real Gaps, Not the Ghost Stories

This pass was a nice reminder that an audit list is a map, not the territory. One item said haptics were completely unimplemented. The repo disagreed: `AuraHaptics` already existed, account activation already fired success feedback, account removal already had warning feedback, and even the music surface had a stray direct `UIImpactFeedbackGenerator` call. The real bug was narrower and more interesting: the app had some haptics, but not on the interaction seams the checklist actually cared about.

So the fix stayed surgical. We taught `AuraHaptics` one more trick with a selection pulse, then wired feedback into successful chain changes and pull-to-refresh on News, Gas, and Receipts. Receipts also gained an actual refresh gesture instead of just standing there looking refresh-adjacent. This is the kind of polish work that matters because it respects the user’s action at the right semantic moment, not just whenever a button happens to be tapped.

The naming audit had a similar “ghost versus bug” shape. The provider type was already correctly Alchemy-backed; the embarrassing part was the filename. Shipping `infura.swift` full of `AlchemyGasPricingProvider` code is like labeling a kitchen drawer “spices” and keeping batteries in it. Nothing explodes, but everyone wastes time. Renaming the file to `AlchemyGasPricingProvider.swift` fixed the smell without inventing a larger refactor.

The documentation gap was the last real hole. Publicly meaningful types like `Chain`, `EOAccount`, `TokenHolding`, `NFTService`, `ContextService`, and `ShellServiceHub` had enough implicit knowledge baked into them that a new engineer was expected to read minds. We added API comments where the names carry product meaning or persistence meaning, especially around chain identity, account scope, token scope, and shell wiring. Boring? Slightly. Useful? Extremely. Good docs are like labels in a restaurant kitchen: nobody praises them during a calm shift, but chaos gets much worse when they are missing.

### The Nine-Tab Problem

This ship-gate fix was not about a crash. It was about product honesty.

`MainTabView` had grown into a nine-tab control panel: Home, News, Gas, Music, Receipts, Profile, Search, ERC-20, and NFTs. The trouble was not that those secondary surfaces were broken. The trouble was that the tab bar was advertising every internal route as if it were equally core to the Phase 0 product. That is how release chrome turns into a junk drawer.

The fix was to separate "real top-level navigation" from "still-valid auxiliary surfaces." We introduced an explicit tab-bar visibility policy in `AppRouter`, kept the release tab bar focused on the core five tabs, and moved Search, Receipts, NFT Tokens, and ERC-20 detail flows behind auxiliary presentation in release builds. Debug builds still expose everything directly, which keeps development and QA convenient without shipping the whole backstage area in the main chrome.

The useful lesson: maturity is not binary. A surface can be implemented, tested, and still not deserve a permanent seat in the public tab bar. Good release polish is often less about deleting features and more about putting each feature in the right doorway.

### The Face ID Ghost

This one was pure configuration archaeology. The ship checklist warned that Face ID might be declared without a real implementation, which is exactly the kind of App Review mismatch that can waste a day for no product value at all.

The actual codebase told a simpler story: there is no `LAContext`, no `LocalAuthentication`, no biometric policy evaluation, and no `NSFaceIDUsageDescription` anywhere in the repo-visible plist or config files. What *did* exist was an empty `Auralis.entitlements` file, which is the configuration equivalent of leaving an unlabeled key on the ring and hoping nobody asks what door it opens.

### Music Receipts: Teach the Existing Ledger a New Dialect

This pass was a good example of how architecture tickets go wrong when they confuse “new behavior” with “new subsystem.”

- The music plan wanted playlist events, dry-run facts, and music-specific policy denials. The trap would have been inventing a parallel audit trail like `MusicAuditStore` and then spending the next month pretending it was “temporary.” We did the opposite. The new code rides the exact same rails as the rest of Auralis: `ReceiptDraft`, `ReceiptStore`, payload sanitization, SwiftData persistence, and the generic timeline/detail UI.
- The new piece is a translator, not a second database. `MusicReceiptEventLogger` gives the music domain a typed vocabulary with stable dotted triggers such as `music.playlist.created` and `music.auto_organization.run`, plus one consistent payload shape. Think of it like teaching the house stenographer music notation instead of hiring a second stenographer who only follows the band.
- Playlist wiring had one subtle gotcha. The create path runs through the old `PlaylistPersistenceStore` actor, while the new receipt logger is `@MainActor`. Shoving the logger directly through that actor boundary would have been concurrency soup. The fix was to let the persistence seam return a small sendable snapshot after save, then log on the main actor afterward. Same truth, less actor-crossing drama.
- We also extended the existing `ActionPolicyGate` instead of replacing it. A blocked music action now *can* emit a second, music-shaped receipt, but the global `policy.denied` fact still lands first. That matters because the app already has one policy story; music is just adding domain detail to it, not staging a coup.
- There was no real auto-organization implementation in the active tree, so we avoided fake UI theater. Instead we added a narrow dry-run service seam that emits a receipt now and gives the future organizer a real place to plug in later. That is much better than burying “TODO: remember to log this someday” in a plan doc and calling it architecture.

The lesson is pleasantly reusable: when a product area needs richer facts, first ask whether the existing ledger is missing vocabulary or missing plumbing. Most of the time, the answer is vocabulary. Build the translator, not a second courthouse.

- The second half of the work answered the more practical question: “fine, but where are the *real* music mutations?” The answer was less glamorous than the ticket taxonomy and more useful than pretending. Playlist creation already had a live UI seam, so it now emits receipts after successful persistence. Playback and queue transitions were the other genuine shipping path, so `AudioEngine` became the active seam for `music.playback.started`, `music.playback.completed`, and `music.queue.changed`.
- The important engineering choice there was injection without global sprawl. The shell now hands the shared engine a `MusicReceiptEventLogger` after `ModelContext` exists, which lets the engine write shared receipts without learning how to build stores or containers for itself. That keeps the DJ booth playing records instead of also moonlighting as the courthouse clerk.
- We also had to be careful not to let playback receipts lie. Completion logging is tied to the track that actually finished, auto-advance is marked as such, and queue-change receipts are emitted only after the next or previous transition successfully lands. The app already had stale-load and cancellation logic; the receipts needed to respect that reality rather than write fan fiction about what “probably” happened.
- The final gap turned out to live in the AuraPlay sync seam, not in some missing future screen. The persisted-library sync already classifies playable versus metadata-only items, normalizes sparse NFT metadata, projects shared NFT rows into the AuraPlay store, and runs as a system-owned music task. So the missing taxonomy moved there: `music.media_classified`, `music.metadata_override.applied`, `music.export.created`, and `music.background_task.run` now come from the wallet-scoped sync path with one shared correlation ID. That is the grown-up version of finishing the ticket. Instead of inventing fake buttons just to satisfy an enum, we taught the code that already does the work to leave a paper trail.

So we resolved the discrepancy in the honest direction: no biometric feature, no biometric declaration, no empty entitlement stub lingering around to imply otherwise.

The lesson is straightforward: App Review cares about the contract your binary advertises, not the excuses you planned to give later. If a capability is not real, remove every trace that suggests it might be.

### The Nested-Type Cleanup That Fought Back

This one looked like a boring lint chore at first: move a few helper types out of `SearchRootView`, `NFTService`, and `AlchemyTokenHoldingsProvider`, let SwiftLint stop complaining, go home. Naturally, it was not that simple.

- **The first trap was fake simplicity**: nested helper types are easy to move and surprisingly easy to break. `NFTService.RefreshPhase` was not just an implementation detail; other views were referring to that nested type name directly. Pulling the enum out without leaving a breadcrumb broke the loading UI immediately. The fix was to keep the extracted type at file scope for cleaner organization, but restore the old API shape with a compatibility `typealias` inside `NFTService`.
- **The second trap was naming collisions wearing business casual**: a freshly extracted search presentation enum compiled fine in isolation, then helped trigger ugly type-inference fallout elsewhere. Renaming it to a more specific file-scope type avoided the generic-looking `Content` collision and kept the public surface boring again, which is exactly what you want from support types.
- **The useful pattern**: if you are refactoring for structure rather than behavior, preserve outward-facing names until you can prove nobody relies on them. Think of it like moving plumbing behind a wall: yes, the pipes can change shape, but the faucet should still be where the kitchen expects it.
- **The last twist was tooling, not code**: after the helper extraction and targeted rule suppressions were in place, Xcode’s SwiftLint build phase kept replaying the exact same warning set with stale line mappings, including warnings pointing at lines that now contain unrelated code or already-correct `.toggle()` usage. Build and tests stayed green, file diagnostics stayed clean, and the warning list still read like a time capsule. Lesson: sometimes the bug is not “fix more source,” it is “the lint invocation or issue navigator is serving cached history dressed up as fresh evidence.”

### Four Bugs, Four Different Failure Modes

This round of fixes was a good reminder that "the app works most of the time" is not the same thing as "the app is safe under stress."

- **The oversized image trap**: `NFTImageView` was using `URLSession.data(from:)`, which is wonderfully convenient right up until a hostile or absurdly large media file shows up. That API buffers the whole payload before your code gets a vote. In a feed full of user-controlled NFT metadata, that is like agreeing to let strangers wheel mystery crates into your living room before checking the label. The fix was to stream bytes instead, reject obviously too-large responses up front, and stop once the payload crosses a hard cap.
- **The invisible persistence failure**: the ERC-20 holdings screen already detected local write failures, but the empty-state UI ignored that message and showed a generic state instead. So the app knew the truth and then politely lied to the user. The fix was not another retry or logging tweak; it was making the empty-state path actually surface the storage failure when that is the real problem.
- **The query parameter that vanished into the ether**: `AlchemyNFTService` exposed `spamConfidenceLevel`, passed it into query construction, and then quietly never added it to the URL. This is the software equivalent of a light switch connected to nothing. The fix was straightforward, but the lesson matters: if an API surface promises behavior, verify the plumbing all the way to the request boundary.
- **The stale count mirage**: `trackedNFTCount` looked like live state in parts of the UI, but it was really a denormalized value with only a couple of write paths. That meant resets, restores, or cleanup flows could leave the count stale while the UI presented it as fresh truth. The fix had two parts: prefer a live count derived from persisted NFTs where the UI needs freshness, and also synchronize the denormalized field during persistence/reset flows so the stored value does not drift forever.

The common theme: the real bugs were not syntax bugs. They were trust bugs. We were trusting convenience APIs, trusting a UI branch to show the right state, trusting a parameter made it to the wire, and trusting cached metadata to stay truthful. Those are exactly the bugs that survive happy-path testing and show up later wearing a fake mustache.

- Image transport error mapping pass: this was the difference between “the internet is hard” and “we know what actually happened.” `ImageLoader` was flattening every transport failure into `.networkError`, so offline mode, timeouts, and other URL-session failures all produced the same generic message. The fix was to preserve offline and timeout cases distinctly while leaving the rest in the generic network bucket, which keeps retry behavior intact but gives the user more honest feedback. Lesson: not every network failure deserves a bespoke taxonomy, but offline and timeout almost always do because they imply different next actions.

- Receipt timeline fallback cleanup: this was a tiny diff with an outsized honesty benefit. `ReceiptTimelineRecord` was decoding stored payloads with `try?` and quietly replacing any corrupt blob with an empty payload, which meant the timeline skipped the existing corruption log path and erased useful scope/search context without leaving tracks. `StoredReceipt` already had `decodedDetailsOrEmpty()` for exactly this scenario, so the fix was simply to stop bypassing it. Lesson: duplicate fallback code is where observability goes to die.

- Account receipt durability pass: this was the same fire-and-forget smell wearing a different jacket. `ReceiptBackedAccountEventRecorder` launched a detached task for every account add/select/remove or chain-scope receipt, which meant `AccountStore` could finish its mutation while the audit write was still floating around in the background waiting to maybe happen. The good news was that the surrounding account APIs were already async, so the fix did not need gymnastics: make `AccountEventRecorder.record` async, await it inside `AccountStore`, and keep receipt-write failures non-fatal by logging them inside the recorder instead of dropping account mutations on the floor. Lesson: if you already have a structured async boundary, use it instead of sneaking background work past the contract.

- Receipt logger contract fix: this was one of those bugs where the type signature was telling a bedtime story instead of the truth. `ReceiptEventLogger` returned `Result<ReceiptRecord, Error>`, but internally it launched a detached `Task` and then immediately returned a synthetic failure every time, even when the receipt write later succeeded. That meant durable writes looked like failures and fire-and-forget writes looked like a defined contract when they really were not. The fix was to make the logger’s write methods properly async, await real persistence in async flows like context refresh and music-index rebuilds, and keep tap-driven UI actions non-blocking by wrapping the awaited logger call in a local `Task`. Lesson: if persistence is asynchronous, the API needs to admit that plainly instead of inventing a fake synchronous answer.

- ENS configuration honesty pass: this was a classic case of a fallback hiding the real fire. `ENSResolvers.makeLiveClient` was using `try?` when loading provider configuration, so a missing RPC URL and an actually broken provider config both got flattened into the same “provider unavailable” story. That made the UI sound calm while the app had no idea whether configuration was absent or invalid. The fix was to preserve those two failure shapes as `ENSResolutionError.missingProviderConfiguration` and `ENSResolutionError.invalidProviderConfiguration`, teach the unavailable client to throw the specific stored error, and pin the behavior with focused resolver tests. Lesson: graceful fallback is good, but only if it does not erase the reason the system failed in the first place.

- ERC-20 persistence scope bug: this one was a nice reminder that “invalid data” only matters if you define what invalid means in the code actually making the decision. `TokenHoldingsStore` was using `NFT.normalizedScopeComponent`, and that helper only rejects empty or whitespace scope, not arbitrary malformed wallet strings. The real ship bug was that empty account scope silently returned from `upsertNativeHolding` and `replaceERC20Holdings`, which made the UI think persistence had succeeded when nothing was written. The fix was to throw `TokenHoldingsStoreError.invalidAccountAddress(...)` for empty scope and pin that with a regression test in `PrivacyResetServiceTests`. Lesson: before you “tighten validation,” verify the real normalization contract or you will fix the bug you imagined instead of the bug users can hit.

- Newsfeed tag restoration: the “Category Selector” placeholder turned out to be pointing at a real relationship that had simply never been wired through. `NFT.tags` still exists, `Tag` still exists, and the expanded card just was not using them. We replaced the fake row with real tag chips derived from persisted tag names and colors. Classic lesson: sometimes the right fix is not “delete the placeholder,” it is “finish the plumbing the placeholder was awkwardly hinting at.”

- Final newsfeed ship trim: the expanded NFT detail card was still rendering a fake “Category / Category Selector” row marked in code as a placeholder. That is exactly the kind of unfinished UI that slips through because it does not crash and still makes the product feel half-answered. The fix was simply to remove it. Better no affordance than an affordance-shaped shrug.

- Release-readiness metadata pass: this was one of those audits where half the job was fixing code and the other half was refusing to fix ghosts. The shell boundary was missing the kind of `///` summaries that make future contributors less likely to treat `ShellStore`, `ShellServiceHub`, `ContextService`, and `AccountStore` like mysterious black boxes, so that surface now has real API breadcrumbs instead of telepathy requirements. The camera-permission scare turned out to be stale because `NSCameraUsageDescription` was already present in `Info.plist`, but it was still worth verifying before pretending it was fine. Pasteboard access also got the “show me the exact code path” treatment: Auralis reads from `UIPasteboard.general.string` only on an explicit Paste tap and writes to it only on an explicit “Copy ID” action, which means the remaining privacy work is App Store Connect paperwork, not another hidden background-access bug. We also checked the `AuraTrustLabel` colors against the app’s actual dark surface palette and confirmed the warning pill still clears contrast requirements, then cleaned up the unfinished orange-dot placeholder and the commented-out `SystemImage` dead code so the release stops shipping little pieces of “we meant to come back to this later.”
- Account receipt schema drift bug: this one was a SwiftData trap disguised as an account-store failure. `AccountReceiptRecorderTests` built a tiny in-memory schema with `EOAccount`, `NFT`, `Tag`, and `StoredReceipt`, which worked right up until `AccountStore.removeAccount(...)` started using the shared cleanup helper that also deletes `TokenHolding`, music-library rows, and search history. The crash message blamed `TokenHolding`, but the real bug was test infrastructure lying about the app’s persistence surface. The fix was to stop hand-curating the schema in that suite and reuse `PrimaryStoreSchema.schema` instead. Lesson: if a test is exercising shared cleanup paths, a “small convenient schema” is usually just future drift with better marketing.
- AuraPlay legacy-removal trust rule: we finally stopped leaving the most dangerous music migration question half-open. If AuraPlay persistence fails to open, Music must not quietly limp along in a fake “probably saved” mode. The app should show an explicit unavailable state, offer recovery actions if it can, disable any action that looks durable, and record the failure through diagnostics or receipts when that path exists. This is one of those boring product calls that saves future pain: users can forgive “temporarily unavailable” much faster than they forgive “you let me organize my library and then threw it away.”
- The other two music decisions also stopped wobbling. Playlists are staying, but they are moving into AuraPlay ownership instead of squatting forever in the AI-era folder. And the shell playback chrome is staying too, which means mini-player and now-playing need a real AuraPlay-native rebuild rather than a ceremonial deletion. Translation: the renovation plan is no longer “tear out the old room and see what feels missing later.” It is “keep the feature promises, move the plumbing, and stop lying about which walls still matter.”
- Two-container cleanup boundary bug: the next crash was more revealing than the first one. Once the test used the primary schema, `deleteAccountScopedSupportData(...)` immediately tripped over `AuraPlayMediaItem`, which exposed the real design mismatch: the helper was trying to delete AuraPlay entities from the primary store context even though AuraPlay lives in its own `AppModelContainer`. That is like the front desk trying to reorganize records in a completely different building because both places technically belong to the same hotel brand. The fix was to make the cleanup helper schema-aware with `modelContext.container.schema.entity(for:)`, so it only fetches or deletes models that are actually registered in the current container. Lesson: when persistence is split across multiple containers, cleanup code must respect those borders just as much as reads and writes do.
- Receipt-retention contract clash: after the container-boundary crash was gone, the failing account-recorder test revealed a subtler bug. Removing an account deleted all prior `StoredReceipt` rows for that address, then wrote the final `account.removed` receipt, so the history surface could prove only the ending of the story and none of the setup. Meanwhile, logout/reset still correctly wanted a full receipt wipe. The fix was to stop treating receipts as ordinary per-account support data during account removal or overwrite, while keeping `deleteAllShellSupportData()` responsible for clearing them during explicit reset flows. Lesson: audit history is not just another cache. If a receipt exists to explain that an action happened, deleting it inside the same action’s cleanup path is basically shredding the evidence on the walk back to the desk.

- Ship-readiness reality check: one review note was a genuine blocker and the rest needed a more skeptical eye. The blocker was the chrome-level context inspector. In release builds, a user could tap the gyroscope pill and open a sheet full of internals like context provenance, freshness state, and receipt-linking details. That is excellent developer scaffolding and questionable production chrome. The fix was to leave the inspector available in debug builds only, mask correlation IDs in the related receipt failure logs, and stop shipping the Home energy card's preview-only copy to release users. Same lesson three times: if something exists to help engineers debug, do not accidentally promote it to a customer-facing feature.

- Networking hardening, round two: this was the “sunny day versus real weather” pass. The NFT provider had a one-way degraded-mode latch, which meant one bad 5xx could push the app into a permanently stripped-down metadata path until restart. That is less graceful degradation and more like a hotel permanently switching to emergency lighting because one breaker tripped once. The fix was to keep degraded fallback scoped to the failing request instead of turning it into a session-wide personality change.

- Networking hardening, round three: this was the “stop lying about freshness” pass. The live shell was accidentally wiring `URLSession.shared` into providers that already had their own timeout policy, which is like buying four seatbelts and then choosing to drive without any of them buckled. The provider factory now only injects a session when we explicitly mean to override defaults. Gas pricing also learned to admit when it is showing stale cache data instead of repainting yesterday’s estimate as “updated now,” the audio engine stopped using `URLSession.shared` for remote downloads and now retries only the failures that deserve a second chance, and native-balance refreshes finally keep the useful HTTP/provider context instead of collapsing into a blank shrug. The broader lesson: fallback behavior is only trustworthy when the app can still explain what kind of fallback the user is seeing.

- Wallet Status productization: once we decided the chrome sheet was a real production feature instead of a debug hatch, the standard changed completely. A gyroscope icon plus “Context Inspector” copy is acceptable engineer bait and mediocre customer UX. The fix was not to hide it better; it was to make it act like a shipped feature. The release build now exposes the sheet, the entry pill reads like wallet status instead of a secret panel, schema-flavored and pointer-flavored labels were stripped out, and the body copy now talks about wallet details, sync state, shortcuts, and recent updates in plain language. The rule of thumb here is simple: if users can open it, they should not need to think like the app’s internal telemetry pipeline to understand it.

- The NFT fetch contract also got stricter in a good way. `NFTFetcher` used to return partial collections when later pages failed, which sounds merciful until you realize the app could then persist and present an incomplete wallet as if the refresh had basically succeeded. We changed the behavior to fail the refresh instead of smuggling a truncated inventory through the happy path. In other words: if the moving truck only delivers three rooms of furniture, do not declare the house fully furnished.

- Gas and token providers needed honesty more than optimism. The gas path was willing to hand back expired cache data after a failed refresh, and the view model would happily stamp it “updated now,” which is the software equivalent of slapping today’s date on yesterday’s newspaper. That fallback is gone. On the ERC-20 side, enrichment failures were getting flattened into generic warnings even when the real problem was authorization or provider availability. The provider now preserves those distinctions so we only degrade when the problem is truly “temporary metadata turbulence,” not “your credentials are wrong” wearing a fake mustache.

- The image loader got a similar truth serum. Non-2xx image responses were being treated like mysterious decode failures, which is how a 404 ends up pretending to be broken image bytes. The loader now recognizes HTTP status failures explicitly, so a missing image looks missing, a rate-limited host looks rate-limited, and retry affordances only show up when a retry is actually sensible.

- ENS trust also became less invisible. The underlying web3 client still requires an explicit resolution mode, but Auralis now records when a network ENS result came from an offchain-enabled path instead of making every network resolution look identical. That sounds small, but trust boundaries are exactly the kind of thing that should not hide inside implementation details like a raccoon in the walls.

- Another pre-ship issue list needed the usual reality filter. Some tickets were real but needed a different remedy than the brief suggested, and some were simply overstated. `NSCameraUsageDescription` already existed, so the runtime-crash warning was stale, but the copy was wrong for the active QR wallet flow. We updated it to tell the truth: the camera is used for wallet QR scanning and playlist cover capture. That is the kind of metadata bug that looks boring right up until App Review asks why your permission prompt is talking about the wrong feature.

- The Home energy card was another honest bug hiding behind pretty UI. `EnergyCardView` had configurable inputs, but Home never supplied anything beyond `Date()`, so users always saw the same “Warming up / Morning energy” story as if the app had psychic powers and a broken watch. Instead of pretending the data is live, the card now shows a visible preview state and the call site carries a TODO pointing at the missing real data source.

- Search indexing got a small but important actor cleanup. The local search index builder was doing its dictionary-building and sorting work from a `task(id:)` path rooted on the main actor. That is fine until a wallet gets large and the search screen starts doing calisthenics on the UI thread. The fix was not “cache more view state and hope”; it was snapshot the model data into value types on the main actor, rebuild the index in a detached task, then publish the finished value back to the view. Heavy prep offstage, UI update back on stage.

- One other ticket got rejected on contact with history. A proposed optimization suggested caching `HomeTabView` derived data into `@State` so the body would stop recomputing it. That sounds tidy, but this repo already has the scar tissue: the journal has a prior regression note showing that exact pattern caused stale Home UI when the underlying SwiftData records changed without changing simple counts. In this case, “optimize the render path” was really “reintroduce an old bug with a fresh haircut.”

- The haptics pass was worth doing because the app had device feedback in one corner and silence everywhere else. Address submission, QR scan success/failure, and account switching/removal now produce lightweight feedback, but only when Reduce Motion is not enabled. Nice reminder that tactile polish should still obey accessibility instead of freelancing as “optional delight.”

- Release secrets and actor cleanup: this round was a useful reminder that pre-ship issue lists are often a mixed bag. The release-secret concern was absolutely real. Both app xcconfigs use an optional include for `Secrets.local.xcconfig`, which is convenient locally but also means CI could produce a Release archive without an Alchemy key and only discover the problem when the app crashes on launch. The fix was to add a Release build phase that fails the build if `AURALIS_ALCHEMY_API_KEY` is missing or still looks like placeholder text. Much better to fail in the factory than after the box reaches the customer.

- The `GasPriceCache` note was also real, but the proposed remedy was too dramatic. The issue was not “invent a whole shutdown lifecycle”; the issue was “actor cleanup is happening from the wrong isolation context.” Since the project already builds with Swift 6 and already uses `isolated deinit` elsewhere, the right move was the small one: switch `GasPriceCache` to `isolated deinit` so its cleanup task is cancelled on the actor executor instead of from a concurrency gray area.

- Several other scary bullets turned out to be false positives once the code got inspected instead of merely accused. `NFTFetcher` already has retry/backoff logic, the ERC-20 path already has provider retry controls, receipt/ERC-20/NFT rows already expose accessibility identifiers in active flows, and `Playlist` plus `MusicLibraryItem` were present in the codebase all along. This is a classic engineering lesson: a checklist is a lead, not a verdict.

- Persistence hardening pass: this one was less glamorous than a UI polish round and much more important. The app had a few places where local writes still happened right on the main actor, which is the software equivalent of making the cashier leave the register every time a box needs to be restocked in the back room. `AccountStore`, `TokenHoldingsStore`, `SearchHistoryStore`, and `SwiftDataReceiptStore` now push their mutations through model actors so saves happen off the UI path instead of freezing the front desk while SwiftData does paperwork.

- The receipts path also stopped treating one corrupted blob like a building-wide fire alarm. `StoredReceipt` used to throw on bad payload decode, and several `SwiftDataReceiptStore` read APIs would happily propagate that failure outward. Result: one rotten `detailsData` value could poison export and timeline reads for everything around it. The fix was to fail soft for decode-at-read time, log the corruption, and fall back to an empty receipt payload instead of taking the whole receipt surface hostage.

- Privacy reset needed one more truth-in-advertising pass. The reset service dutifully cleared persisted selection and local support data, but the live `ShellStore` was still holding the active wallet in memory like a bartender keeping your tab open after you already paid. That meant “Clear Local Privacy Data” could succeed and still leave the app visibly signed in until the next launch. The fix was to keep `PrivacyResetService` focused on storage cleanup and have `SettingsView` explicitly tell the shell to log out once the reset finishes. Storage clears the shelves; the shell turns off the lights.

- ENS cache reset had a sibling bug hiding in the wiring. The app behaved like there was one global ENS cache, but the live resolver factory and the reset service were each quietly constructing their own `ENSResolutionCacheStore`. Clearing one store while another resolver kept its own in-memory snapshot is like changing the whiteboard in the hallway while the person in the room keeps reading their private notebook. The fix was to share one cache-store instance at the production composition layer and lock that seam down with a boundary test proving a reset empties the live resolver’s cache immediately.

- Privacy reset had one more hole in the hull: it cleared search history, receipts, token holdings, and caches, but it left persisted `NFT` rows and `MusicLibraryItem` rows sitting in SwiftData. That meant the app could say “local privacy data cleared” while the device still held the wallet-derived inventory the rest of the product is built around. The fix was to add a dedicated SwiftData-backed derived-data reset seam and make the privacy reset call it alongside the other storage cleanup, with a regression test that seeds both models and proves they are gone afterward.

- Privacy reset then needed a second pass, because “we split the work into services” is not the same thing as “the overall reset tells the truth.” The nasty edge case was a later phase failing after earlier destructive work had already committed. That is like a hotel saying “your room was never touched” after housekeeping already threw out half the minibar. The reset flow now has explicit phases: transactional wallet data first, support caches next, AuraPlay persistence after that, and local preference cleanup last. The transactional SwiftData phase still rolls back atomically on failure, while later failures now report exactly which phase blew up, which phases already completed, and that the operation is safe to retry. We also pinned the retry contract with a test that forces AuraPlay persistence to fail once and then proves a second reset run finishes cleanly instead of getting stranded in “half-cleaned forever” limbo.

- The test suite also got a reality check on schema drift. A few SwiftData tests were building tiny hand-picked in-memory schemas that were “close enough” until production code started deleting support data those tests had quietly omitted. That is how you end up with a passing test that has never actually exercised the live graph. The fix was to stop letting each suite freelance its own container and instead point the important destructive-flow tests at a shared `TestModelContainers.primary()` helper that mirrors `PrimaryStoreSchema` exactly. It is the testing version of using the real floor plan instead of sketching a smaller house on a napkin and claiming the evacuation drill passed.

- SwiftData V0 cleanup pass: this one was about trimming waste, not inventing a grand persistence doctrine. `SearchRootView` had been listening to every `ModelContext.didSave` in the process, which meant one save anywhere could make local search rebuild like an over-caffeinated intern hearing a doorbell. That observer now only reacts to the view’s own context. Newsfeed search also stopped doing three separate store fetches and then filtering the live query again in memory; it now issues one scoped fetch with a combined predicate and a bounded limit. On the view side, Home and Profile no longer keep full live NFT/token arrays around just to say “you have 7 things,” the shared NFT detail screen now asks SwiftData for the specific row it wants instead of hauling the whole shelf into the room, and the music library view stopped live-observing the entire scoped NFT set when it only needed resolvable music items for the current library. Finally, AuraPlay cleanup stopped scanning every persisted token row just to remove a few wallet-scoped ones. The lesson is delightfully unromantic: a V0 app still benefits from not making the database do cardio for no user-visible reason.

- SwiftData hardening for the active shell and AuraPlay was one of those bug hunts where the most dangerous problems were not flashy crashes. They were quiet lies. Removing an account used to clear some wallet-scoped rows but leave others behind, which is the persistence equivalent of moving out of an apartment and discovering you still pay for the parking space and the cable box. The shared cleanup helpers now purge receipts and music-library rows alongside holdings and search history, and logout clears the active shell support data instead of pretending that only NFTs and tags count as “local state.”

- Search also got a useful correction in philosophy. The old `SearchRootView` kept broad live `@Query` collections for accounts, NFTs, and holdings, then rebuilt an in-memory index whenever those arrays twitched. That works fine right up until a real wallet shows up with enough inventory to make the main actor sweat. The better move was not a cleverer cache; it was less live baggage. The screen now fetches scoped snapshots when it needs them and lets the parser work from those values, which is more like packing for the trip you are taking instead of dragging every suitcase you own through the airport.

- The music/NFT persistence path got the same “do less surprise work” treatment. AuraPlay sync and library indexing were fetching full NFT graphs and then lazily poking relationships one by one like somebody opening every kitchen drawer while cooking. Those fetches now prefetch the relationships they actually use, and the AuraPlay repository stopped minting a fresh `ModelContext` every time it wanted a count. One context, one read lane, fewer side quests.

- The final cleanup pass fixed a classic scalability footgun in `NFTService`: every scoped refresh ended by scanning the whole store to decide whether shared contracts and collections had become orphaned. That is the database version of sweeping the entire building every time one room gets rearranged. Because contract and collection identities are already chain-scoped here, the prune step now only inspects the affected chain and the candidate shared rows touched by that refresh. Same correctness, much smaller broom.

- One follow-up bug was a reminder that “privacy reset” and “logout cleanup” are not automatically the same thing just because they sound equally destructive. Account removal and logout were wiping the legacy music rows but leaving the newer AuraPlay wallet graph behind, which is like shredding the paper guest list while the VIP list still sits in the iPad at the front desk. The fix was to treat AuraPlay’s persisted wallet/token/media graph as first-class shell support data and clear it alongside receipts, holdings, history, and the older music cache.

- Search needed a second pass too. Moving away from heavyweight live `@Query` collections was the right performance call, but the first version overcorrected and lost the “stay fresh while I’m looking at it” behavior. The repair was not to crawl back to giant live arrays; it was to let the screen keep its snapshot-based indexing and listen for `ModelContext.didSave` events while open. Same lighter memory footprint, but now the shelf gets re-scanned when somebody actually puts a new book on it.

- A tiny testing cleanup earned its keep as well: one fixture helper had a hidden `try!`, which is the kind of shortcut that sits quietly until lint or CI decides today is the day for honesty. Converting that helper to throw normally kept the file explicit about failure without changing the test intent. Small change, better contract.

- Search history needed a quieter architectural cleanup: one persistence domain had somehow ended up with two people holding the keys. `recordCommittedQuery()` already wrote through a `@ModelActor`, but `removeEntry`, `clear`, and `clearAll` were still deleting rows directly from the main-actor `ModelContext`. That split ownership is how tiny convenience shortcuts turn into “why does this store have two mutation rules?” six weeks later. The fix was simple and worth doing: reserve `SearchHistoryStore` for read snapshots and async forwarding, and route every mutation through `SearchHistoryPersistenceStore`. One write owner, one set of transactional rules, much less future confusion.

- Two query-shape fixes landed in the same spirit: stop asking SwiftData for the whole pantry when the UI only needs a snack. Home’s receipt preview was holding a live scoped query for the entire timeline and then taking `.prefix(5)` in memory, which is the data-layer equivalent of unloading the whole truck to hand someone one grocery bag. That now uses a `FetchDescriptor<StoredReceipt>` with the same scope predicate, the same sort order, and `fetchLimit = 5`.

- ENS search had a more subtle scaling smell. `SearchRootView` was fetching every account with `name != nil` and then doing exact lowercase matching in Swift, which works fine until “has a name” turns into “has thousands of names.” The fix was to teach `EOAccount` a persisted `normalizedName` field, index it, and keep it synchronized whenever `name` changes. Search can now fetch exact ENS matches by equality instead of sweeping the whole named-account set into memory and squinting at it afterward.

- That ENS/search fix immediately found the classic follow-up trap: a new persisted field is only “done” when old rows know how to live with it. Existing accounts on disk did not have `normalizedName`, which meant exact ENS fetches could become technically correct and practically invisible. We folded the repair into the same load-time hygiene pass that already fixes stale chain values in `AccountStore`, so older persisted accounts backfill their normalized search key the first time they are read. Same story on the Home receipt preview: the first optimization trimmed the fetch to five rows but accidentally gave up live observation by doing a plain `modelContext.fetch()` inside a computed property. The corrected version uses descriptor-based `@Query` with `fetchLimit = 5`, which is the nice middle ground: small result set, still live, no “wait, why didn’t the UI update?” mystery.

- Provider startup and retry behavior got a realism upgrade too. `AuralisApp` was using `preconditionFailure` when provider configuration was missing, which is fine if your app is a unit test and less fine if it is a shipped product. Launch now degrades instead of detonating. On the fetch side, `NFTFetcher` had retry machinery but still refused to retry provider 5xx failures and generic HTTP server errors, which is like installing a backup generator and then deciding not to use it during an actual outage. The retry policy now gives transient server-side failures another chance, which is much closer to the resilience story the surrounding code was already trying to tell.

- Image loading hardening: this was a good example of the difference between “an issue was reported” and “the issue is real.” Some of the checklist items were stale on arrival, but two image-loader bugs were absolutely real. `ImageLoader` could fall into a permanent-looking error state after one transient network miss because the view had no in-place retry path, and oversized payloads were being funneled through `try?` into the same bland `.invalidData` bucket. The fix was intentionally surgical: add a retry affordance only for retryable network failures, preserve the explicit oversized-file failure mode, and lock the related tests to serialized execution so the shared URLProtocol mock stopped sabotaging its own evidence.

### SwiftData Audit Remediation: Stop Treating the Storage Room Like a Junk Closet

This was one of those passes where the app already looked serious, but a few persistence seams were still acting like they expected a friendly demo environment instead of a real user with a long-lived store.

- The first fix was the app-launch survival instinct. `AuralisApp` used to treat a primary SwiftData load failure like a fire alarm wired directly to `fatalError`. That is fine until a migrated store gets weird or the local file goes sideways. The new behavior is much more adult: log the failure, fall back to an in-memory container, and show a visible warning banner so the app admits that today’s memory is a whiteboard, not a filing cabinet.
- The NFT graph got a custody hearing. `NFT.Image`, `NFT.Raw`, and `NFT.AcquiredAt` are owned children, but the schema had been relying on implicit relationship behavior while the cleanup path only manually pruned shared `Contract` and `Collection` rows. That is how orphaned data starts breeding in the attic. The relationships are now explicit about cascade ownership, and the shared-model cleanup code finally matches the actual ownership model instead of hand-waving at it.
- Receipts stopped reading the whole diary just to answer one question. `ReceiptTimelineView`, `ReceiptDetailView`, and the wallet-status sheet were all observing broad `@Query` result sets and then filtering in memory. That works until the receipt table gets old enough to vote. Those screens now fetch only the scoped records they actually need, which is both faster and less likely to repaint half the UI because one unrelated receipt changed across the room.
- Undo finally became real instead of theoretical. Because the app installs a prebuilt container, the correct move was not a magical scene modifier overload; it was attaching an `UndoManager` to the primary container’s `mainContext` and then making user-facing destructive flows stop sneaking through background model actors when undo semantics matter. Playlist deletes and search-history clears now go through the main context, which means the app’s “eraser” actions finally use the same desk the undo ledger is sitting on.
- Preview stability also got a reality check. A few previews were creating partial containers with just `Playlist.self`, which is the SwiftData version of building a dollhouse and forgetting the staircase. We introduced `PreviewModelContainers` so previews use real in-memory schemas for both the primary store and AuraPlay store. Less “works on my canvas,” more “actually matches the production graph.”
- The last cleanup was the performance-and-boundary sweep: account listings now sort in the fetch instead of in memory, tracked NFT counts use `fetchCount`, NFT refresh snapshots stop loading every contract and collection in the store when only one chain matters, and the playlist persistence actor no longer accepts live `NFT` models across the actor boundary. That last one is worth remembering because actor isolation bugs are like loose floorboards: they may not drop you today, but they absolutely know where you walk.

The lesson from this whole pass is very warehouse-manager coded: production persistence is not just “we saved some rows.” It is crash behavior, ownership, query scope, preview honesty, and not letting every feature rummage through the same boxes from the wrong side of the room.

### SwiftData Truth Serum: A Relationship on Paper Is Not a Cleanup Strategy

This bug was the persistence version of a fake emergency exit painted on a wall.

- `EOAccount` had a nice-looking `nfts` relationship with `.cascade`, which *sounds* like deleting an account should also delete its NFTs.
- The real app never actually uses that relationship to scope NFT ownership. NFTs are persisted and queried by `accountAddressRawValue` instead.
- That meant removing or overwriting an account deleted the account row and left the wallet’s NFT rows behind like forgotten luggage in the lobby.

The fix was not to write a more inspirational comment about cascade rules. The fix was to make `AccountPersistenceStore` explicitly delete every `NFT` whose `accountAddressRawValue` matches the normalized account address before deleting or overwriting the account row.

The regression coverage also taught a second lesson. A first attempt to prove the fix in `AccountStoreTests` ran straight into a SwiftData fixture quirk around ad hoc NFT graph insertion. Rather than pretend that harness fight was the same as the production bug, the regression was moved into `PrivacyResetServiceTests`, where NFT fixture persistence was already proven to work. That is a very senior-engineer move: when a test harness lies to you, stop arguing with it and relocate the proof to firmer ground.

The sticky lesson: **schema declarations are contracts, not magic spells**. If your live write path uses string scope and not the declared relationship, the cleanup logic has to follow the live write path too.

- AuraPlay reset learned the same lesson from the opposite direction. The app already had a dedicated AuraPlay SwiftData store, but privacy reset was clearing it by deleting SQLite files underneath a still-live `ModelContainer`. That is the persistence equivalent of yanking the floorboards out from under someone who is still standing in the room. The repair was to make the normal path delete AuraPlay rows through the live container with a model actor, then keep the file-deletion service only as a fallback for the special case where the container never came up in the first place. The regression test matters because it proves the part users actually feel: reset, stay in the same launch, write new AuraPlay data again, no weird ghost state.

- The main app store also graduated from “trust me, SwiftData will figure it out” to an explicit versioned schema and migration plan. Before the fix, `AuralisApp` installed the primary store with a raw list of model types, which works right up until the day the schema changes and you discover your migration story was written in invisible ink. The app now builds its root `ModelContainer` manually with `AuralisPrimaryStoreSchemaV1` and `AuralisPrimaryStoreMigrationPlan`, then injects that container into the scene. There is only one schema version today, which is perfectly fine. The important part is that the runway exists before the next migration emergency, not after.

- Playlist persistence got its own quiet hardening pass too. The code already treated `Playlist.id` like a primary key, but the schema was still basically shrugging and hoping nobody would ever save two rows with the same UUID. SwiftData’s unique semantics are slightly sneaky here: duplicate IDs do not explode, they coalesce into one stored row. That is still exactly what we want, because the important invariant is “one persisted playlist per identifier,” not “a dramatic exception was thrown.” At the same time, `tracks` stopped being an implicit relationship and became an explicit one with `.nullify`, which is the correct deletion story for a playlist that references NFTs it does not own.

- The indexing and query pass was the classic performance version of tightening bolts before the bridge gets busier. Search history, receipts, music library rows, and the AuraPlay persistence models now have compound `#Index` definitions that match their real scope and sort predicates instead of relying on full scans as data grows. The accompanying count-path cleanup also stopped several hot code paths from fetching whole model arrays just to ask “how many?” or “does one exist?” SwiftData has `fetchCount`; the grown-up move is to let the store count its own shelves instead of dragging every box into the aisle first.

- Bulk delete APIs earned their keep in the final cleanup round. A few reset paths were still fetching every row into memory only to delete them one by one, which is the database equivalent of emptying a warehouse by carrying each crate through the front office. Those paths now use store-backed bulk deletes for token holdings, receipts, search history, derived NFT/music support data, and live AuraPlay rows. Same behavior, less pointless lifting.

- Pinned-actions corruption handling: `HomePinnedItemsStore` had a classic “recovery” bug that was really a data shredder in a polite hat. If stored pinned-item JSON became corrupted, read paths logged the decode failure and returned `[]`, which was tolerable for display, but the next toggle write would happily overwrite the bad blob with a fresh array and make the old state unrecoverable. The mutating path now fails closed with a real store error instead of treating corruption as an empty set. That is the safer engineering instinct: when local state smells wrong, do not casually rewrite history.

- Tiny pre-ship cleanup, useful lesson: one of the earlier “safe” fixes turned out to be too severe for real product behavior. `HomePinnedItemsStore` had been changed to fail closed on corrupted pinned-item JSON, which protected the old blob but also meant the user could get stuck unable to pin or unpin anything until local storage was manually wiped. We changed the mutation path again so it now clears the corrupted blob, logs the repair, and writes fresh state on the next toggle. That is the better balance here: preserve safety, but do not leave the user trapped in a permanently broken preference screen because one `UserDefaults` value went bad.

- Gas freshness honesty also got one more polish pass. The gas provider already distinguished stale fallback data, but warm in-memory cache hits were still being reported upstream as `.live`, which is yesterday’s leftovers wearing a chef hat. The provider now reports a dedicated cache source and the view model treats both fresh-cache and stale-cache results as cached presentations instead of pretending they came straight off the wire.

- Another pre-ship review pass had a similar theme: some scary-looking checklist items were stale, and some were absolutely worth fixing. `NSCameraUsageDescription` was already present, and the privacy-manifest worry around `CryptoKit` hashing turned out to be a false alarm after checking Apple’s current required-reason API categories. But `GuestPassCard` really did run a perpetual shimmer with no Reduce Motion escape hatch, so the card now respects `accessibilityReduceMotion` instead of insisting every user wants the same amount of motion. That is one of those bugs that can hide in plain sight because the animation looks “nice” right up until it makes someone feel awful.

- The loading surface got a small but important copy cleanup too. `NFTNewsfeedLoadingView` was speaking fluent developer status message: “Fetched X NFTs. Parsing metadata before save.” Technically true, product-wise clunky. The wording now sounds like an app talking to a person instead of a progress log talking to another progress log.

- The Chrome context inspector needed the same intervention. It had quietly drifted into “developer basement panel” territory, showing raw provenance strings, a schema version token, and clipped correlation IDs as if normal people wake up hoping to compare UUID fragments over coffee. The fix was not to remove the signal, but to translate it: provenance now speaks plain language like “Loaded from cache” or “Freshly fetched,” the version area is framed as app version info instead of schema jargon, and the refresh action now says what it actually does for the current wallet scope.

- The receipts timeline also got a render-path cleanup. `ReceiptsRootView` was rebuilding its decoded receipt records and filtered snapshot straight from `body`, which is exactly the kind of thing that works fine until a timeline gets large and SwiftUI starts asking for fresh values more often than you expected. The decoded snapshot is now refreshed from a keyed task into local state, so the view body mostly consumes prepared data instead of doing all the sorting and filtering work inline.

- One more small polish fix landed in the external NFT links. The OpenSea and explorer buttons were using hardcoded hex gradients, which is a fast way to get a button that looks “branded” in one context and weirdly out of place in another. Those buttons now lean on semantic app colors instead of frozen hex values.

- Networking hardening pass: this one was a good example of how “works on a sunny day” is not the same thing as “ship-ready.” The ERC-20 provider had pagination loops that trusted the backend like an overly optimistic intern. One repeated cursor or one endless stream of empty pages and the sync could hang forever. We added explicit stall detection, then taught the provider to admit when enrichment metadata failed instead of quietly serving placeholder rows with a fake smile.

- The RPC path got the same reality check. Native balance loading used `URLSession.shared`, took one swing, and if it missed, `ContextService` basically shrugged and erased the balance from the snapshot. That is not resilience; that is amnesia. The provider now has explicit timeout and retry policy, `ContextService` reuses the last balance for the same wallet/chain scope on refresh failure, and both RPC clients now read JSON-RPC error envelopes instead of pretending every HTTP 200 is a happy ending.

- Another useful lesson from this round: test fallout is often the most honest reviewer in the room. Changing `tokenHoldings(...)` from “array only” to “holdings plus warning” immediately surfaced every place the repo had quietly encoded the old contract. Fixing those tests was not bookkeeping; it was the proof that the new behavior was actually wired end to end.

- Another ship-readiness pass was a good reminder that issue lists need source control, not just confidence. One claimed blocker said the app would crash on camera permission because `NSCameraUsageDescription` was missing; the bundle already had the key. One claimed dead branch in the loading UI said `progressValue < 0` was impossible; the current code still allows negative `itemsLoaded`, so that branch is very much alive. The real bug was `ShellStore`: it stored an in-flight refresh task while that task captured the store strongly, which is the classic “I locked myself in the room from the inside” retain cycle. The fix was to let the task hold the refresh coordinator directly and only talk back to the store weakly when the refresh finishes, then pin that behavior with a test that drops the last strong reference while a refresh is suspended and proves the store can deallocate anyway.

- The next cleanup pass was less about one crash and more about honesty in the UI and honesty in the code layout. `ProfileCardView` and `HomeTabView` were carrying their own prompt-generation recipes plus ENS display resolution, which is a bit like asking the waiter to also butcher the fish and tune the piano. The logic now lives in small helper types so the views mostly handle state and rendering while the deterministic artwork recipes stay testable and reusable.

- The News feed also stopped copying NFT IDs like a pickpocket. Hitting “Copy ID” now shows a visible confirmation pill and success haptic instead of silently stuffing text onto the pasteboard. At the same time, the touched Home, Profile, Energy, and Newsfeed surfaces moved more visible copy to `String(localized:)`, and the Home energy card is no longer trapped behind `#if DEBUG`. It now ships as an explicit preview card, which is much better product behavior than a feature-shaped ghost only developers can see.

- Another pre-ship pass turned up a nice example of why visual bugs can be more dangerous than they look in code review. `ProfileCardView` had the correct avatar image path and the correct fallback icon path, but the fallback icon lived in an unconditional overlay `else` branch. Result: users with a perfectly loaded avatar still got the generic person glyph stamped on top like the app did not trust its own success. The fix was tiny and absolutely worth it: only show the fallback icon when there is no avatar image.

- The guest-pass shimmer had a smaller but more subtle problem. `GuestPassCard` started its infinite border animation from both `onAppear` and `onChange(of: accessibilityReduceMotion, initial: true)`. That is the sort of duplication that looks harmless until motion settings change mid-session and you realize you may have launched two forever-animations that both think they are in charge. We cut it down to one source of truth and let the accessibility-aware `onChange` own the behavior.

- The newsfeed scope got a defensive seatbelt too. `NewsFeedListingView` builds a SwiftData `@Query` from the active account and chain during initialization. That can be okay if the parent view is always rebuilt with a fresh identity, but tab containers are notorious for keeping children alive longer than your intuition wants. Instead of betting the feed on lifecycle folklore, the parent now gives the listing an explicit scope-based `.id(...)`. New wallet or new chain, new listing identity, new query. Boring and reliable is exactly what you want there.

- The failing `HomeTabLogicTests` suite turned out to be a tidy little logic trap in the aurora prompt builder. `HomeAuroraArtworkSupport` correctly computed `"subtle star patterns"` for invalid wallet input, then quietly threw that value away by only appending the pattern atom inside the valid-address branch. That is the kind of bug that makes a fallback path look implemented while still never being reachable. The fix was to append the pattern atom unconditionally and keep the address-signature token gated to real wallet input.

- Swift Testing macro gotcha: one failing test compile turned out to be two separate splinters that looked like a forest fire. Re-enabling the `todo` SwiftLint rule immediately blocked the test target on a leftover `TODO` comment in `HomeTabView`, which is a nice reminder that lint rules are only useful if the codebase can actually live with them. Then `ProviderAbstractionTests` started producing a dramatic pile of macro-generated `@const` noise plus one real concurrency error. The real bug was a `#expect(throws:)` closure returning `[NFT]` across a `sending` boundary instead of discarding the value, and the suite declaration was also the only one written inline with `@Suite`, which did not help readability or diagnosis. Once the suite was normalized and the throwing expectation stopped trying to smuggle actor-isolated data through the macro, the test compile went back to behaving like a grown-up.

- Another Swift Testing smoke bomb showed up in `AccountStoreTests`. Xcode sprayed the test target with `@const` and `@section` macro errors, which looked catastrophic and were mostly theater. The real issue was three `#expect(throws:)` closures returning `@MainActor` values like `EOAccount` and `AccountRemovalResult` instead of `Void`. Swift Testing tried to move those results through a `sending` boundary, the compiler quite reasonably objected, and the macro expansion then covered the walls in misleading debris. The fix was gloriously boring: assign the async results to `_` inside the throwing expectations so the closures only prove the error contract and do not try to carry actor-isolated payloads anywhere.

- Bug hunt: the home avatar fallback looked harmless until the math got audited. `ProfileCardView` was choosing one of eight `testProfile-*` assets, but the asset catalog only had seven. That meant one out of every eight deterministic fallbacks quietly disappeared into `nil`. The fix was simple and surgical: bind the selection logic to the real asset count instead of an imaginary eighth image.

- Another quiet gremlin lived in the home prompt caches. Both `HomeTabView` and `ProfileCardView` were evicting `Dictionary.keys.first`, which feels like "oldest" if you squint at it long enough, but Swift dictionaries do not promise LRU semantics. The cache now keeps explicit insertion order so eviction is predictable instead of vibes-based.

- Preference persistence got a sharper edge. `HomePinnedItemsStore` used to log JSON encode failures and move on as if the pin succeeded. That is the software equivalent of nodding confidently while dropping the package in a ditch. The store now throws so callers can surface the failure instead of lying to the UI.

### SwiftUI Pre-Ship Cleanup: The Bugs That Were Real, Not Just Loud

This pass was a good reminder that not every pre-ship checklist item deserves equal panic. A few reports looked scary but turned out to be either stale, speculative, or already contradicted by the repo. The worthwhile fixes were the ones tied to concrete code paths with clear downside.

What actually got fixed:

- `ImageLoader` stopped minting a brand-new `URLSession` for every image cell. In a scrolling feed, that is like giving each shopper their own grocery store instead of sharing carts and checkout lanes. The loader now uses one reusable default session with the same timeout policy, which keeps connection pooling intact and avoids needless session churn.
- `NFTImageView.swift` kept its synchronous cache fast path so already-cached images can appear immediately in reused cells, while image fetches stopped using `URLSession.shared` and now run through an explicit session with request/resource timeouts. That is the difference between “eventually this cell might load” and “fail fast enough that scrolling still feels sane.”
- `HomeTabView` dropped an unnecessary `AnyView` wrapper around the sparse-state section. This was not a dramatic crash bug, but it was a real structural-diffing tax for no gain. SwiftUI already knows how to handle that conditional when you let it.
- `HomeTabView` and `ProfileCardView` were both carrying prompt caches in `@State` dictionaries with no eviction. That is fine for five minutes and questionable for a long session. Both caches are now capped so the app does not quietly turn deterministic prompt generation into a memory souvenir collection.
- `GalleryGrid` now cancels the previous regenerate task before starting a new one, and it also cancels on disappear. Before that, repeated taps could create a small swarm of overlapping image-generation tasks, which is exactly the kind of bug that makes a UI feel “heavy” without leaving a neat stack trace behind.

The useful lesson here: a good ship review is not “fix everything anyone can imagine.” It is “separate real defects from architectural opinions, then fix the ones that can actually hurt users or destabilize the release.”

### Dead Code Sweep

We removed four confirmed-unreferenced UI leftovers after a project-wide reference audit:

- `Auralis/DataModels/TagViews.swift`
- `Auralis/Aura/Auth/LoginTitleView.swift`
- `Auralis/Aura/Newsfeed/ConnectWalletView.swift`
- `Auralis/MusicApp/AI/V1/DetailView.swift`

This was a nice reminder that “file exists” is not the same thing as “feature exists.” `TagViews.swift` was the most interesting one: it looked substantial, but the entire view stack was orphaned. It was basically a fully furnished apartment with no doors leading into it.

We validated the cleanup with a full project build, which passed. That matters because dead SwiftUI can still be accidentally wired through previews, test helpers, or stale project references. In this case, the build agreed with the grep pass: the code was just sitting there, haunting the place.

### Dead Code Sweep, Round Two

A second pass removed more truly orphaned files:

- `Auralis/DataModels/NFTAnimation.swift`
- `Auralis/DataModels/NFTExamples.swift`
- `Auralis/MusicApp/AI/Audio Engine/Playlist/PlaylistStore.swift`
- `Auralis/NFTMetadataAnalyzer.swift`

This round was more interesting because some “unused” code was only unused by the app, not by the test target. `Password.swift` and `ReceiptResetService.swift` looked dead at first glance, but both still have test coverage hanging off them. That is exactly the kind of trap that turns a cleanup into a stealth regression if you move too fast.

The practical lesson: dead in production code and dead in the repository are not the same thing. Sometimes a file is no longer in the product path but is still part of the test contract. If you want it gone, the right move is to remove or rewrite the tests intentionally, not pretend the dependency is not there.

### Aha! Moment

Misleading filenames are a real tax. `NFTImageView.swift` looked suspicious until inspection showed it still houses live support types like `CachedAsyncImage` and `ImageLoader`. The filename was stale; the code was not. Good cleanup work is less “delete everything dusty” and more “confirm which dust is load-bearing.”

### Pitfall

Do not assume a file named like a feature entry point still contains the feature entry point. This codebase has a few places where a file’s name reflects its past life, not its current contents.

### SwiftUI Integrity Pass

This round was less “one giant bug” and more “a pile of small paper cuts that could absolutely gang up on the UI.” The recurring theme was that several views were doing just a bit too much work at exactly the wrong time: during render, on the main actor, or inside fixed layouts that looked fine until Dynamic Type or a smaller phone showed up and started asking rude but fair questions.

What changed:

- `ReceiptPayloadValueView` stopped building recursive identity signatures for every array element just to create row IDs. We switched to stable enumerated indices for array rendering and replaced the rigid 120-point label rail with a `ViewThatFits` fallback. Translation: the receipts UI now spends less time playing “guess who I am” with nested JSON and more time just showing it.
- `ReceiptDetailFact` got the same treatment. The old fixed-width label column was the UI equivalent of insisting every suitcase must fit the same overhead bin. Now it adapts.
- `NewsFeedListingView` now precomputes filtered results instead of refiltering the full query-backed NFT array every render. It also stopped forcing every card to consume the entire viewport height, which was a little too eager on smaller devices.
- `CachedAsyncImage` and `ImageLoader` were the biggest concurrency win. Network fetch plus image downsampling no longer piggyback on `@MainActor` work triggered from initialization. The view now drives loading with `.task`, while decode/downsample happens off-main. This is one of those fixes that rarely gets applause but absolutely earns fewer hitches.
- `NewPlaylistView` dropped a synchronous `Data(contentsOf:)` read from the Image Playground callback. Blocking the UI thread to load image data is the sort of move that works fine right up until it doesn’t, usually while a user is tapping the screen wondering why the app got philosophical.
- `HomeTabView` now caches its derived receipt previews and music counts into state refreshed on scope changes instead of repeatedly remapping and refiltering the same query data every render.
- A handful of UI ergonomics got tightened up too: `GuestPassCard` now sizes its animated mask relative to the card instead of dragging an 800x800 effect across every device, `EnergyCardView` and `RecentlyPlayedMiniCard` now reuse formatters instead of minting new ones on demand, and the mini/now-playing controls plus newsfeed action rail picked up explicit accessibility labels and better hit targets.

The practical lesson here is that SwiftUI usually behaves well when views stay honest: declare UI, react to state, and keep anything expensive or side-effectful out of the hot path. Once a view starts doing filtering, formatting, network work, file IO, and identity synthesis at render time, it is basically trying to be a stage manager, lighting rig, and lead actor all at once. That show gets messy.

### Privacy and Concurrency Paper Cuts: The Bugs That Look Administrative Until They Ship

This round of cleanup had two different flavors of risk, and both are the kind that love to hide behind “probably fine.”

First, the Swift 6 concurrency audit. Two service wrappers were using `@unchecked Sendable` as a hall pass:

- `AlchemyNFTService` had mutable request-degradation state hanging off an otherwise sendable service wrapper
- `Web3EthereumNameServiceClient` wrapped a third-party ENS client that the compiler could not prove safe to share across async boundaries

The right fix was not to keep arguing with the compiler. `AlchemyNFTService` now keeps its mutable mode behind a tiny internal actor while the public wrapper stays genuinely `Sendable`. The ENS client took a different route: instead of sharing one questionable object forever, it now stores only the RPC URL and builds the `EthereumNameService` on demand per request. Same behavior, much cleaner ownership story. The compiler stopped complaining because the code actually became safer, which is usually a good sign that the compiler is being annoying for the right reason.

Second, the App Store metadata cleanup. This was the paperwork version of “the plane flies great, shame about the missing wings.” The app already used:

- camera capture for playlist artwork
- photo-library selection for playlist artwork flows
- `UserDefaults` and `@AppStorage` across search, pinned items, ENS caching, passwords, and shell state

But the bundle metadata had holes:

- `Info.plist` was missing camera and photo-library purpose strings
- there was no `PrivacyInfo.xcprivacy` manifest at all

That is exactly the kind of issue that waits patiently until the first review submission, then smacks you with a rejection email. The fix was intentionally small and explicit: add the usage descriptions, add a privacy manifest, and declare the required-reason API usage we can substantiate today, which is `UserDefaults` with reason `CA92.1`.

There was one more small but memorable lesson in tooling humility. `Journal.md` and `AGENTS.md` existed on disk the whole time, but the Xcode project tools could not see them because the workspace uses filesystem-synced groups and those root docs sit outside the synced folders. In other words, the files were real, but not real to that particular lens. Good reminder: when a tool says “missing,” always ask “missing where?”

### Regression Cleanup: When "Optimization" Turns Into a Hallucination

Three regressions showed up immediately once the uncommitted changes were reviewed together:

- `MiniPlayerView` wrapped the whole mini player in a `Button` while the transport controls inside it were also buttons. That is the SwiftUI equivalent of putting a big plastic cover over the dashboard and then wondering why the radio knobs feel weird. The outer tap target could interfere with the inner controls, so the fix was to restore the original non-nested tap behavior for opening Now Playing.
- `NewsFeedListingView` cached filtered NFT results in `@State` and only refreshed them when a few coarse triggers changed. Same count, different records? Stale UI. The view had basically started remembering yesterday's groceries because the number of bags looked the same.
- `HomeTabView` did the same trick with derived counts and recent-activity previews. It cached live SwiftData-derived information into local state, which meant the dashboard could quietly drift away from reality if records changed without changing the total count.

The fix in all three cases was a nice reminder that not every repeated computation is a caching opportunity. If a value is cheap enough and directly derived from live source-of-truth data, letting SwiftUI recompute it is often the more correct move. Local state should own user intent or view-local lifecycle, not become a sidecar database because it feels "faster."

### Swift 6 Test Harness Cleanup: The Compiler Became the Grumpiest Reviewer in the Room

A batch of test failures turned out not to be product bugs at all, but Swift 6 concurrency rules finally collecting old debts from the test target.

What broke:

- several test doubles conformed to `Sendable` protocols while still keeping mutable arrays and dictionaries as plain stored properties
- a couple of tests pushed `@MainActor` types like `NFTService`, `NFTFetcher`, and `AppRouter` across nonisolated boundaries
- the URLProtocol-based network mocks used shared static handlers, which is basically a polite way of saying “global mutable state with good intentions”
- parameterized tests had helper case types that were not `Sendable`, which made Swift Testing’s macros unhappy

The cleanup was surgical:

- stub state that needed mutation moved behind actors or tiny synchronized wrappers
- tests that were already dealing with main-actor production types were explicitly marked `@MainActor` instead of pretending they were actor-neutral
- generic `TestCase` helpers were made `Sendable` so Swift Testing could safely package arguments
- the URLProtocol mocks were rewritten to use explicit `nonisolated(unsafe)` handlers with a documented test-only invariant: install, run one request flow, clear immediately

This was a good reminder that test code is still code. A flaky test double is just production chaos in a fake mustache. Swift 6 is forcing the suite to be honest about who owns mutable state and which execution lane a type actually lives on. Annoying in the moment, very useful in the long run.

One small but telling follow-up bug showed up in `ShellStatusPresentationTests`: the suite was calling main-actor presentation helpers from a nonisolated context, then trying to carry a tuple containing `ShellStatusAction` back across that boundary. The compiler quite reasonably objected. The right fix was not to weaken the production API, but to admit what the test was already doing and mark the suite `@MainActor`. That is a very Swift 6 lesson: if the code lives on the main actor, say so plainly and stop pretending it is actor-agnostic.

The same pattern showed up again in `NFTCollectionDetailPresentationTests`, except this time it surfaced as a runtime breakpoint while exercising a perfectly ordinary collection filter. The filter logic was fine. The test was not. `NFTCollectionDetailView.makePresentation(...)` is main-actor isolated because it lives on a SwiftUI view type, and the test tried to call it from a nonisolated synchronous context. Marking the suite `@MainActor` fixed the crash without diluting the production boundary. Same lesson, louder voice.

Another smaller but useful cleanup landed in `NFTImageLoaderTests`. The tests were still assuming `ImageLoader` begins fetching in `init`, but the production loader had already been modernized to start work from `loadIfNeeded()` so SwiftUI can trigger it from `.task`. In other words, the app moved to explicit lifecycle-driven loading, while the tests were still living in the old “constructor does everything” universe. The fix was to update the tests to call `loadIfNeeded()` before asserting on post-load error state. That keeps the tests aligned with the real contract instead of pressuring the production code back toward hidden initializer side effects.

### Release Hygiene and Refresh Churn: The Quiet Bugs That Make an App Feel Expensive

This pass was all about the kind of bugs users rarely describe with precision. They do not say, “your dependency seam is inconsistent” or “your refresh path is issuing too many SwiftData fetches.” They say, “the app felt weird,” which is much more annoying because they are usually right.

Three things changed:

- `AccountSwitcherSheet` stopped freelancing its own `AccountEventRecorder` and now uses the same `ShellServiceHub` factory path as the rest of the shell. Before that, one sheet was quietly bypassing the service boundary like a side door with no badge reader.
- `NFTService` got a performance cleanup in the persistence path. Instead of repeatedly fetching the same persisted NFTs, contracts, and collections for every incoming item, it now snapshots those records once per refresh and reuses them. Same end result, much less “ask the database the same question 400 times and act surprised when the UI looks busy.”
- Old metadata-analysis scaffolding was removed from the shipping target. `NFTMetadataAnalyzer.swift` and `NFTExamples.swift` were not part of the product path, but they were still sitting in the app target like rehearsal props left on stage during opening night. That is especially awkward when the analyzer carries hardcoded wallet lists and emits logging you absolutely do not need in a release build.

There was also a smaller cleanup sweep:

- the commented-out metadata-analysis task was removed from `AuralisApp`
- stale commented blocks were removed from `NowPlayingView`
- an unused `playlistImage` state property and a ticket-style placeholder comment were removed from `NewPlaylistView`

The lesson here is simple: “not currently executed” is not the same as “harmless.” Dead release-path code still increases review surface, privacy risk, and cognitive noise. And performance bugs are often less about one catastrophic algorithm and more about a hundred tiny repeated calls taking turns kneecapping the main actor.

### Main-Actor Surgery Without Knocking Over SwiftData

The follow-up bug here was subtle and annoying: we had “fixed” the NFT refresh path, but most of the expensive metadata interpretation still lived inside an `@MainActor` service. Translation: the app was still doing a decent amount of thinking on the UI lane, just with fewer database laps.

The fix was to separate interpretation from mutation.

- Networking trust and fallback cleanup: this round fixed four small-but-real seams that all sat in the “looks fine until prod traffic or privacy expectations get involved” category. The ENS client now actually respects its `allowsOffchainLookup` flag instead of always taking the offchain path and then pretending the toggle mattered. The NFT inventory client now uses an intentional shared session with explicit request/resource timeouts, which finally makes that path behave like the RPC, token, and image providers instead of freelancing on `URLSession.shared`. Gas pricing also got its memory back: if the cache has an expired estimate and the refresh fails, Auralis now keeps the stale estimate instead of dropping the screen into an avoidable empty failure state. And the ERC-20 provider stopped shredding HTTP context into a generic “something went weird” bucket. Now non-retryable status failures keep their status code and API message long enough for the UI to say something concrete, which is much better than the old “provider did not respond cleanly” shrug.

- `NFTMetadataUpdater` now knows how to build a pure metadata patch as a sendable value.
- `NFTService` snapshots only the raw metadata inputs it needs, computes those patches in a detached task, then comes back to the main actor to apply the results to SwiftData-backed `NFT` objects.
- cleanup failure receipts were also corrected to use the known requested account and chain instead of reverse-engineering scope from whatever stale NFT array happened to be around after a failure.

This is one of those engineering moves that feels a bit like moving a kitchen remodel into the garage so dinner service can keep running. The heavy chopping and prep happen off to the side; the final plating still happens where the real dishes live.

The practical lesson: if a model object is actor-bound, do not try to brute-force it across concurrency boundaries. Extract the pure inputs, do the expensive interpretation elsewhere, then apply the result back at the ownership boundary. That pattern is safer, easier to explain in code review, and much less likely to produce the kind of “it builds, but now persistence is haunted” regression that ruins a Friday.

### Local Package Footing: Start Small, Wire It For Real

This change was intentionally modest, because the dangerous version of “let’s modularize” is when somebody opens a chainsaw before deciding which wall is load-bearing.

- We added a new local Swift package named `AuralisPrimaryModels` at the repo root and wired it into the app target as an actual package dependency, not as a decorative folder that happens to contain Swift.
- The package currently exports `PrimaryStoreCopy`, which is tiny on purpose. It gives the app one real integration point for primary-store UI copy without forcing a rushed migration of the actual SwiftData model graph into a package before the seams are ready.
- The first usage lives in `AuralisApp`, where the local-storage recovery alert now reads from the package instead of another hardcoded app-local string. Small move, real dependency, zero theater.

The lesson is classic renovation logic: when you want a future guest house, first pour one clean concrete pad and make sure the plumbing reaches it. Do not start by trying to relocate the entire kitchen with dinner service still in progress.

### EOAccount Extraction Plan: Stop Pretending a String-Scoped System Is an Object Graph

This planning pass answered a very specific packaging question: can `EOAccount` move into `AuralisPrimaryModels` without dragging half the app behind it? The useful answer was “yes, but only after we make the schema tell the truth.”

- On paper, `EOAccount` and `NFT` still have a direct SwiftData relationship. In practice, the app already behaves mostly like an ID-scoped system. Queries filter on `accountAddressRawValue`, cleanup deletes by scoped predicates, and `trackedNFTCount` is recomputed from fetch counts instead of walking `account.nfts`.
- That is actually good news. It means the first migration step is not a philosophical rewrite. It is mostly removing a relationship that the app has already outgrown.
- We wrote the migration down as a two-phase plan: first decouple `EOAccount` from `NFT` with minimal churn, then move `EOAccount` into the local package once it no longer depends on the NFT graph. That sequence matters because it separates persistence-behavior risk from module-boundary risk.

The memorable lesson is one architecture keeps teaching in different accents: if the running system already trusts stable IDs more than object references, the model layer should stop cosplaying as a tightly coupled object graph. Better to admit the truth in one controlled diff than let the mismatch keep charging interest.

### Small Defects, Real Consequences

This cleanup round was not glamorous, but it was exactly the sort of work that keeps a release from feeling sloppy.

- `HomeTabView.logout()` used to shrug at SwiftData deletion failures with `try?`. That is the software equivalent of dropping the office keys down a storm drain and marking the task complete. Logout now fails explicitly: if local cleanup throws, we log it, show the user an error, and stop instead of pretending state reset succeeded.
- `AppDeepLinkParser` was passing a token-only chain requirement through receipt routes. Nothing exploded, but it was a logic smell: a receipt route was carrying a backpack full of token assumptions it never used. That requirement is now removed for receipts so the parser says what it means.
- two production error logs were printing wallet addresses as public values during chain-selection persistence failures. Not a crash, but definitely not the kind of observability gift you want to hand over in release logs. Those addresses are now hashed in logs instead.

The lesson is that defect resolution is not always about dramatic stack traces. Sometimes it is about refusing to let “quietly wrong” stay quiet: hidden logout failures, misleading parser wiring, or logs that leak more than they should. That is how a codebase gradually stops surprising you in production.

### Shell State Consolidation: Replacing The Four-Way Argument With One Adult In The Room

This was the big shell refactor the codebase had been asking for in increasingly passive-aggressive ways.

Before the change, the active shell scope was split across four values:

- `currentAddress`
- `currentAccount`
- `currentChain`
- `currentChainId`

That setup worked the same way four people carrying one couch up the stairs “works” right up until somebody turns too early and the whole thing wedges in the hallway.

The new setup puts a real foreman on the job:

- `ActiveShellSelection` is the single address-plus-chain scope.
- `ShellState` is the canonical snapshot of shell control-plane state.
- `ShellAction` is the explicit list of state transitions.
- `ShellStore` is the only owner allowed to mutate shell selection.

The nice part is not just fewer properties. It is fewer *arguments*.

- `MainAuraView` no longer runs a web of shell sync observers.
- `MainTabView` no longer “fixes” chain persistence in `onChange`.
- `AccountSwitcherSheet` no longer writes straight into shell bindings like it found the spare keys.
- gateway/auth flows now activate accounts by sending shell intents instead of poking `currentAccount` directly.

The real war story here was not the reducer itself. It was the migration edge cases.

- The first draft accidentally created the new shell files under a duplicated `Auralis/Auralis/...` subtree. Classic refactor tax: the architecture was cleaner while the file paths briefly looked like a hall of mirrors.
- `HomeTabView` still had a couple of old binding assumptions hiding in its query setup and profile card handoff, which is exactly the kind of leftover that makes a build fail even after the “big” work is done.
- The new shell tests also reminded us that tuple arrays are not automatically pleasant to compare in expectations, which is a tiny but very Swift-shaped papercut.

The payoff is worth it. The shell now behaves like a state machine instead of a negotiation between `@State`, `@AppStorage`, and a few optimistic `onChange` callbacks.

One follow-up bug showed up immediately in review, and it was exactly the kind that architecture refactors love to smuggle in under a fake mustache: cold-start deep links could arrive before `ShellStore` existed, hit `MainAuraView`, and get dropped on the floor. The fix was simple and important. `MainAuraView` now queues the parsed deep link or route error until the store is created and the initial restore has run, then replays that startup routing into the store. In other words: if the user shows up with directions before the front desk has finished booting, we now write them down instead of pretending they never walked in.

We also filled in the reducer test gaps the review called out. `ShellStoreTests` now covers same-account no-ops, inactive and last-account removal, chain persistence failure, deep-link routing and deep-link error surfacing, explicit route-error dismissal, fresh/loading foreground no-op refresh cases, and logout state reset. That is not just more green dots. It means the shell store is now tested on the awkward branches, not just the friendly ones.

### The Service Locator Haircut

The next architecture problem was subtler than the old four-way shell argument, but it had the same bad energy: too much of the UI could still reach into `ShellServiceHub` and quietly ask infrastructure for whatever it wanted. `MainAuraView` was booting real services, `MainTabView` was playing factory bingo for receipts, search, token sync, ENS, and music indexing, and child views were inheriting the same pattern like a family recipe nobody actually likes.

- The important realization was that `ShellServiceHub` is only virtuous as long as it stays in the composition room. Once views receive it directly, it stops being dependency injection and starts being a backstage master key.
- The migration plan for `ARCH-001` deliberately avoids replacing one giant bag with five medium-sized bags wearing fake mustaches. The target is small feature-scoped dependency bundles plus explicit use-case protocols where view code actually needs behavior, not infrastructure trivia.
- The first cut is intentionally narrow: move `MainAuraView` and `ShellStore.live(...)` off the hub first, then tighten `MainTabView` and child surfaces. That sequence matters because it breaks the biggest architectural back-edge without forcing the whole shell through a one-PR demolition derby.

The memorable lesson: a service locator can look tidy in code the same way a junk drawer looks tidy when it still closes. The problem shows up later, when every screen knows where the spare batteries, passport, and mortgage paperwork are supposed to be.

## Engineer's Wisdom

- Dead code removal is only “safe” after verifying inbound references and then building the project. Grep without validation is guesswork.
- Large files attract unrelated responsibilities over time. That is how you end up with domain models living next to abandoned UI experiments.
- The cleanest architecture in the world still loses clarity if old view stacks are left behind after a routing refactor.
- A senior-engineer move here is to treat code archaeology as part of product quality, not as a cosmetic chore.
- SwiftUI performance problems often look tiny in code review. A single formatter in a computed property, one `Data(contentsOf:)`, or one array filter in `body` can seem harmless until it sits on a path that re-renders constantly.
- If a control looks tappable, it should usually be a `Button`. Accessibility is much easier when semantics and visuals are aligned instead of retrofitted later.
- But the inverse also matters: if a region contains other controls, making the whole thing a `Button` can create an interaction turf war. One tap target per job keeps the peace.
- Derived data from `@Query` should stay derived unless you have a strong invalidation story. Caching without complete invalidation rules is just a polite form of lying.
- If a shell selection is conceptually one thing, model it as one thing. Address-now-chain-later is how routing bugs grow legs.

## If I Were Starting Over...

I would put stricter boundaries around feature folders and refuse to let exploratory UI land in `DataModels/`. That one choice would have prevented at least one confusing dead-code pocket.

I would also add a lightweight periodic hygiene pass:

- scan for declaration-only view types
- look for files with zero inbound references
- check whether filenames still match their primary exported types

That is the software equivalent of cleaning the garage before you start storing motorcycles in it.

## 2025-02-14 Config Cleanup Pass

A small but worthwhile configuration sweep landed here. The project was telling two stories about iOS support at the same time: the project-level deployment target said `18.0`, while the app and test targets were all set to `26.0`. Xcode follows the target, so the app was effectively iOS 26-only anyway, but the project file looked like a split-brain system. We aligned the project-level default to `26.0` so the build settings stop arguing with each other.

Privacy metadata also got less poetic and more App-Review-proof. The camera usage string now says what the app actually does: scan a wallet address QR code so the user can add or switch accounts. We also removed the `arkit` required-device capability after confirming the active code paths do not use ARKit or RealityKit. That flag was acting like a velvet rope for devices that had no reason to be excluded.

There was also one dead test file hanging around like an abandoned movie set: `AuralisTests.swift` existed on disk, was fully commented out, and was not even part of the Xcode project. It is gone now. Finally, the app target marketing version moved from `00.00.01` to `0.1.0`, which is much less likely to make App Store metadata look like it was typed during a power outage.

## 2025-02-14 SwiftData Optional Safety Pass

One small bug fix here carried more weight than its size suggested. `NFTMetadataUpdater.applyImagePatch(...)` was force-unwrapping `nft.image` immediately after creating it when nil. In ordinary code that looks harmless. In persistence-backed code, especially with optionals hanging off model objects, it is exactly the kind of shortcut that feels fine until the day it becomes the stack trace.

The fix was boring on purpose: materialize the image value if needed, bind it safely, mutate the local value, then assign it back. No behavior change, no architectural drama, just one less “trust me” in a path that runs during metadata refreshes. Good bug fixes often look like this. They remove a sharp edge before anybody gets the chance to bleed on it.

## 2025-02-14 Search History Starts Moving Into SwiftData

This pass begins the search-history migration by adding a dedicated `SearchHistoryRecord` model instead of treating history like a blob of preferences. That old `UserDefaults` approach worked the way a junk drawer works: technically the batteries and paper clips are stored, but good luck managing scope, recency, deduplication, and deletes without eventually muttering at the drawer.

The new model is intentionally small: account scope, normalized query, display query, timestamp, and a scoped ID that says “one row per normalized query per account.” The important decision was to keep nil-account history as actual `nil` in storage rather than inventing another fake string scope. That keeps the persistence model honest and makes the next store refactor much less likely to grow weird translation logic around a made-up sentinel.

## 2025-02-14 Search History Finishes The Move

The rest of the migration landed cleanly, which is always suspicious but occasionally true. `SearchHistoryStore` no longer serializes one giant JSON blob into `UserDefaults`; it now talks directly to SwiftData through `ModelContext`, does scoped upserts, trims each account to its retention window, and deletes rows like a normal piece of persisted app data instead of pretending to be a settings toggle with ambition.

The wiring changed in the right place too. `ShellServiceHub` now builds the store with a model context, `MainTabView` passes that store into `SearchRootView`, and `PrivacyResetService` clears the same SwiftData-backed rows during local privacy resets. That is the important architectural win: one persistence story, one construction path, and one reset seam.

The testing story got better as well. The old tests were proving that `UserDefaults` could remember a JSON blob. The new tests prove the behavior we actually care about: per-account deduplication, nil-account isolation, max-entry trimming, full clears, and privacy reset clearing persisted search history. That is a much better contract. It tests the restaurant, not just whether the pantry door closes.

## 2025-02-14 Search History Error Propagation

One follow-up review caught a bug that looked administrative until you picture it in a privacy reset flow. `SearchHistoryStore` had moved to SwiftData, but its write paths still behaved like a shrug emoji: save failures were logged and then quietly ignored. That meant `recordCommittedQuery`, scoped clears, and even `clearAll()` could fail underneath the floorboards while callers walked away believing the job was done.

That is especially bad for `PrivacyResetService`. A privacy reset that says “all clear” while search history is still sitting on disk is not a small bookkeeping mistake. That is the software version of a hotel telling you the room was emptied while your suitcase is still under the bed.

The fix was to make search-history mutations throw instead of fail soft. `PrivacyResetService` now propagates those failures properly, and `SearchRootView` handles them like a user-facing product surface should: it keeps the current history snapshot visible, logs the problem, and shows an honest banner instead of pretending the write succeeded. The lesson is simple and worth keeping around: reads can degrade gracefully; destructive writes and privacy actions need a real success signal.

## 2025-02-14 Enum Decode Observability

Another pre-ship review produced a classic engineering trap: a long bug list where some items were real, some were already fixed, and some were just wearing a scary hat.

The worthwhile fixes were the boring, sharp-edged ones:

- `GasPriceEstimateViewModel` moved from `ObservableObject` and `@Published` to `@Observable`, and `GasPriceEstimateView` now owns it with `@State`. Same lifecycle, cleaner alignment with the app’s newer observation model.
- `HomePinnedItemsStore` and `SearchHistoryStore` stopped failing silently on `UserDefaults` encode/decode problems. They still fail soft for users, but now leave log breadcrumbs instead of politely eating the evidence.
- `NFTMetadataUpdater` became a caseless `enum`, which is the type-system version of locking the supply closet so nobody “accidentally” turns a static helper namespace into an instance.

Just as important was what did *not* get changed:

- the `symbolColorRenderingMode(.gradient)` report was stale; current SwiftUI docs and Xcode both accept it
- the prompt-cache eviction complaint was stale; both caches are already capped
- the `URLSession.shared` complaint was stale; `ImageLoader` already uses an explicit session with timeouts
- the “no tests” claim was wildly stale; the repo already has a substantial Swift Testing suite, including coverage for several of the exact areas called out

The lesson: a ship checklist is not a shopping spree. Good pre-release work is equal parts fixing defects and refusing to cargo-cult fixes for problems the code no longer has.

One sharp-edged break *was* real: `NFTService` had evolved from a single `lastSuccessfulRefreshAt` value into a scope-aware lookup keyed by account and chain, but one receipt test file was still behaving like the old property existed. That is the sort of bug that feels petty until it blocks the whole test target and turns release confidence into theater.

The repair was deliberately small. The tests now ask the same question the app asks in production: “for this account, on this chain, when did the last successful refresh happen?” Once the test stopped pretending refresh freshness was global, the test target compiled again and the focused release-safety slice went green.

The lesson is worth keeping: freshness and cache timestamps almost always start life as one innocent value and later become scope-dependent. When that happens, tests should be updated to mirror the real lookup contract immediately, or they become fossilized documentation for an API the app no longer has.

## 2025-04-29 AuraPlay Phase 1: Building The Stage Before Moving The Band

AuraPlay finally stopped being a hopeful folder name and started behaving like a real module boundary.

- The first win was structural honesty. The Music tab now routes through an AuraPlay swap seam with a dedicated `Core`, `Domain`, `Services`, and `Presentation` layout under `Auralis/MusicApp/AuraPlay/`. That matters because rebuilds go sideways when “temporary” files all squat in `App/` and quietly become architecture.
- The second win was dependency discipline. The AuraPlay root no longer knows just about a library repository and playback controller. It now receives queue, artwork, logging, and bundle-configuration seams too. Think of it like replacing a garage full of extension cords with a real breaker panel: each circuit now has a labeled place to plug in, and tests can swap components without touching the live audio engine.
- The third win was paperwork honesty. We removed a motion privacy string that described a feature the repo does not actually implement, then wrote source-backed tests for the Info.plist and privacy manifest. This is exactly the kind of thing that saves you from an App Review conversation that starts with “why does your app claim to do this?”
- We also added the repo-level contracts that keep future AuraPlay work from backsliding quietly: SwiftLint guardrails for `print()` and global audio-engine access inside the module, plus a GitHub Actions workflow that resolves packages, runs SwiftLint, builds the app, and runs tests.

The useful engineering lesson here is that a feature rebuild needs two kinds of scaffolding. The visible kind is folders, models, and views. The invisible kind is contracts: privacy declarations, lint rules, CI checks, and a short architecture note that tells future engineers which walls are load-bearing. Skip the second kind and the first kind eventually turns into a haunted house.

## 2025-04-29 AuraPlay Docs Stop Pretending To Be A Ticket Graveyard

One last cleanup pass turned the AuraPlay Phase 1 plan from a historical ticket ledger into something future humans can actually use.

- The old plan file had done its job. It explained how to translate a greenfield-style ticket stack into this repo, but once the foundation work landed, the remaining value was no longer “which ticket was P1-006?” It was “what is still incomplete, how do I QA this on a phone, what does good look like, and how does Phase 2 start without stepping on a rake?”
- So the doc set got split into the same kind of retained-artifact pattern already used for Phase 0. Instead of one big markdown sandwich with stale acceptance criteria, AuraPlay now has dedicated docs for future work, physical-device QA, UI/design audit, Phase 2 handoff, and a compact LLM context file.
- This is one of those boring-sounding senior-engineer moves that pays off disproportionally. Good documentation is not just “more writing.” It is reducing the amount of archaeology the next person has to perform before they can make one safe change.

The useful lesson: planning docs and memory docs are not the same species. A planning doc is scaffolding while a feature is being built. A memory doc is the map you keep after the scaffolding comes down.

Another pair of failures turned out to be a nice split-screen of “real product bug” versus “test harness bug.”

On the product side, `ContextService` was correctly returning a resolved snapshot for a losing refresh generation during a race, but it only emitted `context.built` receipts for the winner. That meant one caller got a real result and zero audit breadcrumb, which is exactly the kind of observability gap that makes concurrency bugs feel paranormal. The fix was to log the receipt for every resolved refresh result while still keeping only the winning generation as the persisted live snapshot.

On the testability side, `ImageLoader` had hidden its `URLSession` behind a static singleton. That is convenient right up until you need a deterministic test and discover your mock protocol is yelling through the window while the loader is using a different door. The cleanup was simple and worth keeping: preserve the production default session, but allow a test session to be injected. Once the test could bring its own `URLSessionConfiguration` with `protocolClasses`, the video-content-type rejection case became stable again.

That combo is a good engineering reminder:

- racing work should not silently skip receipts just because it loses the UI-update election
- networking helpers should own sensible defaults, but not trap tests behind hidden globals

Another small-but-real cleanup landed in `EOAccountSource`. The decoder already had a compatibility fallback for unknown raw values, which is good. The bad part was that it failed silently and quietly relabeled anything unfamiliar as `.manualEntry`. That is like a hotel front desk receiving a reservation for a room type it does not recognize and just handing the guest a standard key without telling anyone.

The fix keeps the fallback but adds logging when it happens. That preserves resilience for old or future data while giving us a breadcrumb if the stored schema or imported payloads drift. Compatibility is good. Compatibility with amnesia is not.

## 2025-02-14 SwiftUI Ownership Seam for Gas Previews

`GasPriceEstimateView` had a classic SwiftUI ownership smell: it was correctly using `@StateObject`, but it hardcoded creation of its own view model with no injection seam. That makes the production path easy and the preview or test path awkward, which is how teams end up writing “just ignore the preview” comments and then wondering why nobody trusts the component.

The fix was to keep ownership where it belongs and make initialization more honest. The view still owns a `@StateObject`, but now it can be initialized with a caller-supplied `GasPriceEstimateViewModel` when previews or tests need control. Same lifecycle semantics, better seams, less fake helplessness.

## 2025-02-14 Timer Discipline in the Gas View Model

The music engine had a similar kind of timing bug, just wearing a different costume. `AudioEngine.progress` looked dynamic from the outside, but it was really just a computed value sitting on top of a private clock. SwiftUI only redraws an `ObservableObject` when published state changes, so the mini player and now-playing slider were basically staring at a very accurate watch locked in a drawer.

The fix was to make playback position an actual published signal. `AudioEngine` now keeps `@Published private(set) var currentTime`, updates it immediately during seek/pause/stop/load transitions, and runs a small main-actor display loop while playback is active to push fresh values into the UI every quarter second. Same underlying playback math, but now the views hear about it instead of needing telepathy.

## 2025-02-14 Review Triage: Real Bugs Versus Scary-Sounding Notes

Another review pass produced one of the most common late-stage engineering chores: separate the problems from the vibes. A few notes looked alarming on paper, but only some of them were actually bugs.

The real product bug was in the gas screen. `GasPriceEstimateView` used `estimate == nil && !isLoading` as the path to its error state, while `GasPriceEstimateViewModel.setChain(...)` deliberately waited 300 ms before starting the first fetch. That left a tiny opening where the view had no estimate, was not yet loading, and briefly dressed up as a failure. In user terms, it could flash an error before it had even tried. The fix was to give the view model an explicit `phase` (`initial`, `loading`, `loaded`, `failed`) so the UI can tell the difference between “haven't started yet” and “actually failed.” Same data, much better manners.

The `NFTService` note turned out to be a regression-risk seam, not a production bug. The service intentionally preserves the terminal fetch error across `nftFetcher.reset()`, but the behavior was being enforced by comments and careful ordering rather than a test. That is the software equivalent of a fragile glass sign reading “please do not bump this.” The right fix was not to rewrite the production path; it was to add a regression test proving the fetcher still gets reset while the terminal error survives.

The shell-service note was mostly a false alarm wearing architecture language. `ShellServiceHub.live` does call `ReceiptStores.live(modelContext:)` multiple times, but the store is cached by the long-lived `ModelContext` identity, and the existing boundary tests already prove the factories share the same persistence seam. Good note to verify, not a bug to churn.

The macOS stub in `AuralisApp` was also real, just simpler: the project is configured for `iphoneos`, so the conditional `Settings` / `MenuBarExtra` block was dead furniture. That kind of stub is harmless right up until it starts a confusing conversation during release review. Removing it made the app entry point say exactly what the target actually supports.

The lesson here is a classic SwiftUI one: a computed property is not observation. If the UI needs to animate or track something over time, give it a real source of truth that emits changes on purpose.
The gas estimator had a timer pattern that worked, but a little too optimistically. Every refresh tick launched a fresh task to get back onto the main actor, and while `isLoading` reduced overlap, it was not the same thing as having an actual single-flight contract. That distinction matters in refresh code because “probably not overlapping” is how you eventually end up with a support ticket that begins with “sometimes the spinner feels haunted.”

The cleanup kept the timer but changed the control flow. The tick now bridges back to `@MainActor`, immediately checks tracked task state, and only starts a new fetch when no other fetch task is in flight. In other words, the lobby still has a doorman, but now there is also a guest list.

## 2025-02-14 One Source of Truth Means One Actual Storage Path

`ModeState` had a split personality. It read mode through `@AppStorage`, but it also carried a separate injected `UserDefaults` writer closure. In production, the closure was a no-op and `@AppStorage` did the work. In tests, both wrote, but reads still came from the property wrapper. That is the kind of design that looks dependency-injected from ten feet away and then quietly cheats when you get closer.

The fix was to stop pretending there were two equal storage paths. `ModeState` now initializes `@AppStorage` with the injected defaults store when one is provided, so reads and writes finally agree on where truth lives. The app still force-normalizes Phase 0 to `.observe`; it just does it through one pipe instead of two.

## 2025-02-14 Localization Consistency Pass

Localization bugs rarely arrive dressed like bugs. More often they show up as one error type using `NSLocalizedString`, another using raw literals, and a third doing a little of both like it is trying to keep everyone happy. `TagError` had exactly that problem, and `AccountStoreError` was still entirely raw-string based despite clearly being user-facing.

The fix was not glamorous: normalize them. The copy did not need to become more complicated; it just needed to stop freelancing. Once error formatting moved behind explicit localization keys and format strings, the code started telling one story again. That is a useful lesson in product polish: inconsistency is often what users feel, even when they cannot name it.

## 2025-02-14 Chain Label Cleanup

`routingDisplayName` had been taking a lazy shortcut for less-common networks by capitalizing raw values like `arbnova-mainnet`. That produced UI labels with all the elegance of a shipping manifest. The app already had proper human-readable network names elsewhere; this one path was just skipping the nice front door and sneaking in through the loading dock.

The fix was to derive routing labels from `networkName`, stripping only the redundant `Mainnet` and `Testnet` suffixes, while preserving the intentionally short flagship names like `Ethereum` and `Base`. A focused test now covers representative networks so labels do not quietly slide back into hyphen soup later.

## 2025-02-14 Newsfeed Action Honesty

The newsfeed had a classic first-impression bug: a shiny action rail full of buttons that looked ready for social energy, then delivered absolutely nothing. Like, comment, share, and bookmark were all visible in `NewsFeedCardButtons`, all accessibility-labeled, and all wired to empty closures. There was even a fake creator-profile button sitting at the top like a cardboard elevator panel.

The right fix was not to invent pretend behavior. The action rail now keeps only the menu path that actually works today, and the decorative avatar placeholder is no longer advertised as an interactive control. This is a useful product lesson disguised as a UI cleanup: if an affordance is not real yet, do not let it cosplay as shipped functionality.

## 2025-02-14 Search History Persistence Decision

This one is less about a crashing bug and more about putting the right furniture in the right room. `SearchHistoryStore` was living in `UserDefaults`, which is fine when you are saving things like “show captions by default” or “last selected segment.” It is much less convincing when the data starts behaving like a tiny database.

Search history in Auralis is:

- scoped to an account
- ordered by recency
- deduplicated by normalized query
- trimmed by per-account retention rules
- cleared by privacy reset flows

That is not a casual preference. That is persisted app data wearing a `UserDefaults` nametag and hoping nobody asks follow-up questions.

The migration plan is to move search history into SwiftData without making `SearchRootView` pay the price for the persistence correction. The key move is to keep the existing `SearchHistoryStore` API and keep `SearchHistoryEntry` as the UI-facing value type, while swapping the storage engine underneath it. In other words, the front-of-house search UI keeps taking orders the same way, while the kitchen quietly upgrades from a notepad to an actual ticket rail.

There is one deliberate bit of caution here: the initial migration should preserve the current `"global"` no-account sentinel exactly as-is and support a one-time legacy import from the old `UserDefaults` blob. That keeps the first shipping change mechanical and boring, which is exactly what you want from a persistence migration. Exciting migrations are usually just bugs with better marketing.

## 2025-02-14 Rate Limits, Privacy Resets, and Other Ways Software Can Accidentally Lie

This pass was a good example of three different bugs sharing one personality flaw: the app was sometimes technically doing *something*, but not always the thing it claimed to be doing.

First, the NFT rate-limit path. `AlchemyNFTService` already parsed `Retry-After`, which looked reassuring until you followed the baton handoff and discovered `NFTFetcher` promptly ignored it and ran its own exponential backoff anyway. That is like a traffic cop telling you “wait 30 seconds” and the driver responding “I have my own counting system.” The fetcher now honors provider-supplied retry delays when they exist, then falls back to local backoff only when the server gives no guidance. Small change, real production consequence: fewer self-inflicted retries during a rate-limit window.

Second, the privacy reset story stopped leaving fingerprints behind. `PrivacyResetService` already cleared a respectable pile of local state, but it still left the active wallet selection and wallet-scoped pinned home actions sitting in `UserDefaults`. That is not a privacy reset; that is a privacy reset with a forwarding address. The reset path now clears those wallet-linked remnants too, and the settings copy says so plainly instead of overselling the wipe.

Third, the gas screen learned the difference between “cached but still useful” and “cached because the live provider is broken.” The old path would happily fall back to stale gas data after almost any refresh failure, including auth and configuration failures, then present a polite cached state as if nothing especially actionable had happened. That is yesterday's weather report with today's timestamp pasted on top. The provider now only reuses stale cache for genuinely transient failures, keeps unauthorized/configuration failures loud, and maps gas errors into the same kind of user-facing language the other provider surfaces already use.

There was one more cleanup hiding in the wings: a couple of SwiftData writes were still running directly on the main actor in UI code. `AccountSwitcherSheet` chain changes and playlist create/delete flows now push persistence through model actors instead of doing paperwork in front of the customer. The useful pattern here is simple and worth repeating: let SwiftUI own intent and feedback, let model actors own mutation, and do not ask the UI lane to be your file clerk just because the write is “probably small.”

## 2025-02-14 Foreground Refresh Discipline

This pass fixed a shell-level behavior problem that users rarely report in precise terms but absolutely feel. Before the change, the app had no explicit foreground lifecycle policy, so coming back from the background did not give the shell a real chance to ask the important question: “is my active NFT scope still fresh enough to trust?”

The new rule is simple and opinionated:

- foreground resume checks the active account scope against `NFTService.refreshTTL`
- if the data is still fresh, do nothing
- if it is stale, refresh the active scope
- if a refresh is already in flight, leave it alone

That keeps the app from behaving like an overcaffeinated intern who re-fetches everything every time the user glances away for two seconds.

There was a second UX cleanup folded into the same change. The full-screen loading experience now belongs to first-entry bootstrap only. Once the user has already reached the authenticated shell at least once, later refreshes stay in the main UI and surface through shared loading/freshness state instead of kicking the user back to a giant blocking loading screen. Same work, much less drama.

One more subtle but important adjustment: shell refresh work is no longer explicitly cancelled just because the root view disappears during app lifecycle transitions. That does not guarantee iOS will always let background work finish forever, because the OS is still the OS, but it does stop the app from sabotaging its own in-flight refresh the moment the scene changes state. Sometimes stability work is exactly that boring: remove the line of code that keeps pulling the fire alarm.

## 2025-02-14 Refresh Identity And Receipt Scope Fixes

This pass was a good reminder that persistence bugs rarely arrive alone. They travel in a pack, usually wearing different hats and pretending to be unrelated.

The first problem was local NFT tags getting erased during refresh. The network refresh pipeline was rebuilding NFTs from provider data and then merging them back into SwiftData, but tags are not provider data at all. They are local annotations. In practice, that meant a refresh could behave like an overenthusiastic housekeeper who sees sticky notes on your desk and throws them out because they were not part of the original furniture set. The fix was to stop treating tags as refresh-owned state and preserve the existing persisted tags during merge.

The second problem was sneakier. Metadata parsing was allowed to overwrite `tokenId`, but the scoped NFT `id` had already been computed earlier in the refresh flow. That created the software equivalent of changing the label on a filing cabinet drawer without updating the index card in the front office. Dedupe, upsert, and stale-cleanup all depend on stable identity, so the right fix was to reapply refresh scope after metadata mutation so `tokenId`, contract scope, account scope, chain scope, and `id` all tell the same story again.

Receipts had their own identity crisis. Some receipt producers hashed wallet addresses inside the sanitized payload, which is the right privacy move for export-safe payloads, but the timeline model was also trying to recover account scope from that same sanitized payload later. That is like shredding the mailing label for privacy and then asking the mailroom to sort by street address. We split those concerns apart. Receipts now store explicit account and chain timeline metadata separately from the sanitized payload, and the receipts timeline no longer filters by chain implicitly. That matches the actual product rule better: if you are looking at receipts for an account, you should see the account's receipts across chains unless you explicitly choose otherwise.

The last fix was about audit-trail honesty. `AccountStore.createWatchAccount(... overwriteExisting: true)` could log a removal receipt before the underlying save had actually succeeded. That is a dangerous pattern because receipts are supposed to describe facts, not hopes. The fix was to delay overwrite-path receipt emission until after persistence commits successfully, while preserving the existing logical ordering of `removed` followed by `added` for successful replacements.

## 2025-02-14 Scope Freshness And Context Churn Cleanup

This round was all about teaching the shell to stop smearing one scope's state all over another scope's dashboard.

The first bug was a classic “single variable, many realities” problem. `NFTService` kept one `lastSuccessfulRefreshAt` timestamp for the entire app, even though refreshes are scoped by account and chain. That meant refreshing Account A on Base could make Account B on Ethereum look fresh too. The foreground refresh policy would then politely decline to refresh the actually stale scope because some other scope had recently done its homework. The fix was to store freshness by `(account, chain)` scope and make every consumer ask for the active scope explicitly. No more communal toothbrush.

The second problem lived in the chrome/context layer. `MainTabView` was using one refresh trigger for both real remote refresh work and tiny local preference changes like pinning home actions. Because `ContextService.refresh()` always resolved native balance from the provider, a harmless local UI change could quietly cause a network read and a fresh `context.built` receipt. That is the engineering equivalent of ordering a sticky note and getting a forklift. The fix split the path in two: remote-worthy changes still run the full refresh pipeline, while local-only changes rebuild the context snapshot using the cached balance for the same scope.

There was one more audit-trail honesty fix hiding inside that context work. `ContextService` could finish building a snapshot, lose the generation race, and still emit a `context.built` receipt for a snapshot the UI never actually adopted. We tightened that contract so only the winning generation, the one that really becomes active state, gets to write the receipt. If a snapshot loses the race, it loses the receipt too. Receipts should describe what happened, not what nearly happened in a parallel universe.

Finally, we removed a stray `currentCursor` write from the NFT refresh path. It was being persisted to `UserDefaults`, but nothing in the app read it back, scoped it, or reset it intentionally. That made it less of a cache and more of a ghost note left in the attic. Better to delete the fake contract than pretend there is a pagination-resume feature when there is not.

## 2025-02-14 Search History Plan Reset

One planning document had wandered into an alternate timeline where the app had already shipped, users had legacy `UserDefaults` search history in the wild, and we needed a careful migration dance. That would have been a respectable problem if it were real. It is not.

Search history has not shipped yet, so there is nothing to migrate and nobody to rescue from an old storage format. The right move is much simpler: stop writing design fiction and implement the first real version directly on SwiftData. That means no dual-read store, no import pass, no “remove fallback next release” cleanup chore waiting like a booby trap in the backlog.

The useful lesson here is that architecture should match the product timeline, not some generic best-practices screenplay. Migration code is a tax you pay only when history exists. Before launch, it is just extra moving parts pretending to be prudence.

## 2025-02-14 Empty Legacy Folder Cleanup

This was a small cleanup with a useful moral. The repo still talked about `MusicApp/OLD/` like it was a haunted wing of the house: excluded from SwiftLint, mentioned in docs, and treated as something engineers should tiptoe around. The problem was that there was no haunted wing. The folder was empty, not in the project, and not shipping anything.

So the cleanup was straightforward: remove the stale SwiftLint exclusion, delete the empty directory, and stop telling future engineers spooky stories about legacy music code that is not actually there. This is one of those hygiene tasks that pays off by making the repo tell the truth faster.

## 2025-02-14 Explicit Bad-Data Provider Coverage

This one was a testing honesty fix. We already had product-level behavior for unreadable provider payloads: the app classifies decode failures as invalid-response conditions and shows sane fallback copy. The weak spot was lower down. The provider suite did not have a focused case proving that a `200 OK` response with malformed JSON body actually fails at the decode boundary.

That distinction matters. A lot of networking suites are good at testing angry servers and bad at testing lying servers. But a `200` with nonsense in the body is exactly the kind of bug that slips through if you only cover status codes and downstream presentation mapping. It is the API equivalent of a waiter smiling, saying “everything is ready,” and then serving a plate with the ingredients still in the grocery bag.

The fix was small and deliberate:

- `AlchemyNFTService` now accepts an injected `URLSession` while keeping `.shared` as the production default
- `ProviderAbstractionTests` now sends a malformed success payload through the real provider path and asserts that `DecodingError` is surfaced explicitly

The useful lesson: “bad data coverage” is not the same as “some later layer eventually noticed something was wrong.” If the provider contract says “decode this success body,” the tests should prove that malformed success bodies fail exactly there.

## 2025-02-14 Provider Error Honesty And Cache Cleanup

This pass was the software equivalent of replacing a building's emergency signage after discovering half the arrows pointed to “somewhere over there.”

The first issue was error translation. The NFT presentation layer knew how to talk about `NFTFetcher.FetcherError`, but typed provider failures from `ProviderAbstractionError` and `AlchemyNFTService.APIError` were slipping through the cracks and getting flattened into generic “unavailable” messaging. Native-balance and ERC-20 flows had a similar problem: raw `URLError`s could bubble up far enough that the UI stopped being specific and started sounding diplomatic. The fix was to tighten the translation contract. Offline is now a first-class provider state, NFT failures understand provider abstraction and Alchemy API errors directly, and the balance/token surfaces now distinguish offline from ordinary provider unavailability.

The second issue was provider resilience. The NFT envelope insisted on fields like `totalCount` and `validAt`, and the token providers decoded entire arrays in one gulp. That meant one malformed row could take the whole page down with it, which is dramatic behavior for what should have been a recoverable bad-record problem. We switched those paths to lossy array decoding and made the envelope metadata optional where the app already treats it as advisory. In plain English: keep the good crates when one tomato in the shipment arrives cursed.

Then there was retry timing. Several network clients only understood numeric `Retry-After` headers and ignored the equally valid HTTP-date form. A shared parser now handles both styles across NFT, token, gas, and audio download code so server-directed backoff is not interpreted like a half-heard train announcement.

ENS caching also got a long-overdue cleanup. When a name's address changed, the resolver correctly detected `mappingChanged` but left the stale forward cache entry behind like an old mailing label on a suitcase. That meant repeated lookups could keep tripping over yesterday's truth. The resolver now removes the stale entry before surfacing the change, and corrupt ENS cache blobs are discarded on load instead of quietly haunting future launches.

Finally, the keychain password store stopped doing high-wire updates with no net. It used to delete the old secret before attempting `SecItemAdd`, so a failed add could turn “update password” into “erase password and act surprised.” The save path now uses the normal add-or-update flow without pre-deleting the existing item.

## 2025-02-14 Haptics Main-Actor Boundary Fix

This was a classic UIKit-meets-Swift-6 paper cut. `AuraHaptics` looked like a tiny harmless wrapper around `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator`, but UIKit now treats those generators as main-actor isolated. So the code was effectively trying to ring the front-desk bell from outside the lobby and the compiler quite reasonably objected.

The fix was intentionally narrow: mark only `impact(_:)` and `notification(_:)` as `@MainActor` instead of slapping main-actor isolation across the whole wrapper. That keeps the stored `isEnabled` flag lightweight while making the actual UIKit touchpoints obey the real threading contract.

The lesson is simple and worth remembering: when a wrapper exists mostly to hide framework details, it still inherits the framework's isolation rules. A tiny facade does not magically make UIKit non-UI.

## 2025-02-14 Release Secrets And Mode-State Concurrency Hardening

This pass was about two different kinds of honesty: not leaking internal config trivia into release builds, and not pretending Swift 6's actor rules are optional just because an old workaround compiles.

- `SettingsView` had a debug-friendly provider status panel that reported whether the Alchemy key was configured. Useful during development, terrible release behavior. Shipping that is like leaving the restaurant's pantry checklist taped to the front door. The whole section now lives behind `#if DEBUG`, including the trust label, explanatory copy, and status rows.
- `ModeState` also got aligned with the rest of the shell's actor model. It owns `@AppStorage` and `@Published` state that the UI reads on the main actor, so leaving the class nonisolated was effectively asking Swift 6 to stop noticing a race because the code “usually” behaves. The class is now `@MainActor`, and the receipt helper that reads `mode` is explicitly main-actor isolated too.
- The sneakiest bug was the environment fallback. `ModeStateKey.defaultValue` had been using `nonisolated(unsafe)`, which is concurrency for “trust me, I brought a blindfold.” The replacement keeps the protocol requirement nonisolated, but backs it with a main-actor-owned singleton accessed through `MainActor.assumeIsolated`. Same minimal blast radius, much more truthful safety story.
- We also checked the password-store escape hatch. `PasswordStores.test(...)` had no production call sites, so the fix there was prevention: make the plaintext `UserDefaults` store debug-only and say plainly in code that it is test-only.

The useful lesson: pre-ship hardening is often less about adding features and more about removing quiet lies. A release build should not narrate its secret wiring, and concurrency annotations should describe the real ownership model instead of suppressing the compiler until launch day.

## 2025-02-14 Signing Failure From A Ghost Capability

This one was not a Swift bug at all. The project was failing before compilation really mattered because the target still advertised `com.apple.developer.carplay-audio` in `Auralis.entitlements`, and the current signing setup could not provision that capability.

That kind of issue is sneaky because it looks like “the app does not build,” but the real problem is more like showing up at airport security with paperwork for a trip you are not actually taking. Xcode tries to provision the entitlement, cannot find a valid profile path for it, and the whole build stops at the gate.

The fix was deliberately small:

- remove the unsupported CarPlay audio entitlement from `Auralis.entitlements`
- rebuild immediately to confirm the failure was contractual, not source-level

After that, the project built cleanly again.

The lesson: entitlements are part of the product contract, not harmless metadata. If the app is not actively using a capability, leaving the key around is just inviting signing trouble later.

## 2025-02-14 AuraPlay Logging Privacy Fix

This one was a small diff with a very real blast radius. `AuraPlayEntryView` was logging library refreshes with the active wallet address interpolated directly into the message. That is the sort of thing that feels harmless during development and then becomes embarrassing the moment a production log export exists.

The fix stayed narrow on purpose:

- keep the refresh log, because “did the library refresh path run?” is still useful operationally
- remove the raw account address from the message
- replace it with coarse state only: either there is an active account or there is not

In plain English, we kept the breadcrumb and stopped leaving the user's house key next to it.

The lesson: privacy bugs are often not giant crypto failures. Sometimes they are just a well-meaning debug sentence that knows too much.

## AuraPlay Phase 2 Ship-Baseline Reality Check

This pass was less about adding a flashy new subsystem and more about forcing the repo to stop underselling and overselling itself at the same time.

- The undersell was in the live AuraPlay root. The code already had a real Phase 2 persistence spine: SwiftData container, schema, wallet/token/media models, sync service, and a repository that can prefer persisted AuraPlay media over the legacy indexer. But the UI and migration enum were still calling the active path “Phase 1 foundation,” which is like installing a new basement and then leaving a sign on the door that says “temporary plywood only.” We renamed the active stage and updated the copy so the app describes the architecture it actually has.
- The oversell risk was more subtle. The plan talked about search, playlists, playback history, and deterministic integration scenarios in the same breath as the persistence spine, which makes it easy for a future reader to mentally mark all of Phase 2 as “basically there.” That is how later-phase work becomes accidental scope debt. We made the plan say the quiet part out loud: Waves 1 and 2 are the current ship baseline, and Waves 3 and 4 are explicitly deferred.
- We also added a regression test for the migration seam that really matters right now: once a scoped wallet has been mirrored into AuraPlay storage, the library repository must prefer the persisted media graph instead of pretending the legacy indexer is still the source of truth. That is the difference between a migration ramp and a decorative diagram.

The lesson: ship readiness is not just “does the code compile?” Sometimes it is “does the product, the plan, and the tests all tell the same story, or are they each living in a different timeline?”

## AuraPlay Privacy Reset: The Basement Counts Too

This one was a straight-up truth-in-advertising bug. The Settings screen promised that “Clear Local Privacy Data” would wipe local support data, but AuraPlay Phase 2 had quietly moved part of the music inventory into its own SwiftData store under Application Support. So the reset flow was cleaning the kitchen and leaving the basement shelves untouched.

- The root cause was architectural, not visual. `PrivacyResetService` already knew how to clear the main app container, caches, receipts, search history, and token holdings. But AuraPlay persistence had become a second storage boundary, and deletion responsibility never followed it there.
- The fix was to stop pretending that one reset seam still owned all the data. We added an explicit `AuraPlayPersistenceResetting` contract, wired the live reset path through a store-file cleanup service, and taught the privacy reset flow to clear the AuraPlay store alongside the original app data.
- The regression test does the important boring work: create the AuraPlay store artifacts, run the reset, and prove the store file plus SQLite sidecars are actually gone. That is much better than a test that only checks whether somebody remembered to call a method with a reassuring name.

The lesson: whenever you split persistence, you also split the cleanup contract. If you add a new basement and forget to hand the janitor a key, the basement becomes privacy debt.

## AuraPlay Container Lifetime: Stop Reopening The Record Vault

This one was a quieter bug than a failed reset, but it had the same architectural smell: the ownership boundary was in the wrong room. `AuraPlayTabRootView` was creating its own `ModelContainer` inside the view initializer, which sounds harmless until you remember SwiftUI treats view values like stage props, not heirlooms.

- The problem was lifecycle mismatch. `MainTabView.body` can rebuild normally as state changes, and the Music tab subtree can be recreated without meaning “please reopen the AuraPlay store from scratch.” But the container creation lived inside that subtree, so the app was repeatedly reopening the same persistence store and recreating fresh `@ModelActor` services around it.
- The fix was to move AuraPlay container ownership up to `MainAuraView`, where the shell already owns other long-lived services like the shared audio engine and NFT orchestration. The Music path now receives one stable `ModelContainer` instance through `MainTabView` and into `AuraPlayTabRootView` instead of manufacturing a new vault key every time SwiftUI redraws the hallway.
- This is one of those bugs that rarely screams during happy-path demos and still matters before ship. Multiple live containers pointed at the same store are the persistence equivalent of having three bartenders separately convinced they are the only one tracking the tab.

The lesson: in SwiftUI, expensive stateful resources belong to the owner with the longest honest lifetime, not the nearest convenient initializer.

## AuraPlay Store Boot Failure: Degrade The Feature, Not The Process

This was the kind of crash that makes engineers wince because it was technically tidy and operationally reckless. AuraPlay’s store boot used `fatalError` on container creation failure. That is fine for a prototype, less fine for a shipped Music tab behind a normal user tap.

- The failure mode got worse once Phase 2 persistence became the default Music path. A corrupted store file or file-system hiccup no longer meant “AuraPlay is unavailable”; it meant “the app dies when the user opens Music.” That is a bad trade unless the tab is running a nuclear reactor.
- The fix was to make boot failure an availability state instead of an execution state. `MainAuraView` now captures AuraPlay store boot as optional container plus a user-facing fallback message, and `AuraPlayMigrationStage` explicitly resolves back to `.legacy` whenever the Phase 2 store is unavailable.
- The important design choice was containment. We did not create a second recovery architecture or scatter error handling across every AuraPlay dependency. We kept the fallback at the seam where the module gets selected in the first place, which is the right room to decide whether the new record vault is open or whether the app should send users through the old entrance.

The lesson: when a feature-specific store fails to boot, the product should lose the feature slice, not the whole app session.

## AuraPlay Sync Hitch: Let The Front Desk Fetch, Let The Back Room Sort

This one was not a correctness bug so much as a choreography bug. The Phase 2 library sync path was doing more work on `@MainActor` than the UI could politely hide: fetch the wallet-scoped music NFTs, deduplicate them, normalize strings and URLs, sort them, and build the upsert payloads, all while the Music tab was waiting at the door.

- The subtlety here is SwiftData ownership. The source `ModelContext` still belongs to the main actor in this slice, so pretending the whole sync could just “move to background” would be the kind of concurrency fix that writes its own future incident report.
- The real fix was to split the job at the correct seam. The main actor now does the actor-owned fetch and immediately snapshots the relevant NFT fields into `Sendable` value types. Then a detached phase does the heavier in-memory work: deduplication, sorting, string cleanup, artwork URL selection, and request construction.
- We also pulled that detached shaping work into a dedicated request builder instead of leaving a pile of type-level helpers hanging off the sync service. That keeps the service in conductor mode and moves the pure transformation logic into its own instrument case.
- In restaurant terms, the host still checks the reservation book at the front desk because that book lives there. But the host no longer chops vegetables, plates the entrée, and polishes glasses while the line forms at the door.

The lesson: with Swift concurrency, “move it off the main actor” is only a good fix when you first separate actor-owned state access from pure value transformation.

## SwiftData Hardening Pass: Stop Treating The Database Like A Suggestion

This pass was a classic case of the schema saying one thing while parts of the app were quietly behaving like the schema was just inspirational poster text.

- The first bug was account ownership. `EOAccount` claimed it owned `NFT` rows with a cascade relationship, but the refresh pipeline was really just stuffing account addresses into raw string fields and hoping future cleanup code stayed disciplined forever. That is not ownership; that is a sticky note. The fix was to wire a real `NFT.account` relationship and assign it during persistence, so deleting an account now has an actual graph to work with instead of a folklore contract.
- The second bug was playlist durability. Playlists were pointing straight at live wallet `NFT` rows, and refresh cleanup was allowed to delete those rows when they disappeared from the latest inventory. That makes a playlist feel less like a saved crate of records and more like a memo saying “these songs existed once.” The fix was to keep playlist membership as a real SwiftData relationship, archive stale playlist-linked NFTs out of active account scope instead of deleting them, and clear playlists explicitly during privacy reset so destructive cleanup removes the whole shelf instead of leaving empty album sleeves behind.
- The receipt timeline had a smaller but very real honesty problem. Receipt counts were scoped by wallet address but not chain, which meant a multi-chain wallet could look busier than the selected timeline actually was. The fix was simple: filter by both address and chain at the store boundary, not after the fact in our heads.
- Receipt fetches also got a practicality lesson. Asking SwiftData for “latest 20” and then reading the whole table before taking a prefix is like asking a bartender for one lime and making them inventory the entire fruit fridge first. The store now uses bounded fetch descriptors for sequence allocation and limited reads.
- The search and home surfaces got a similar cleanup. `SearchRootView` no longer watches the entire NFT and holdings universe when it only cares about the active account and chain, `HomeTabView` now queries only the scoped receipts it actually shows, and the account switcher pushes account ordering down into SwiftData instead of fetching first and sorting in the view like it is grading papers by hand.
- Another hardening pass exposed a privacy-retention leak wearing a perfectly respectable data model costume. Removing or overwriting an account used to clear the `EOAccount` row and its scoped `NFT`s, but it quietly left wallet-scoped token holdings and search history behind like receipts still sitting in yesterday’s coat pocket. The fix was to centralize account-scoped cleanup, delete those support rows alongside the account, and reuse one `SwiftDataNFTCleanup` helper so destructive paths also prune orphaned `NFT.Contract` and `NFT.Collection` records instead of letting the store collect abandoned filing cabinets.
- The music path got its own lane-discipline upgrade too. The expensive AuraPlay sync and music-library rebuild work was still doing too much store-backed thinking on the main actor. That is the software version of making the maître d' run back to the freezer to recount inventory every time a guest asks for a table. The fix was to move the snapshot and rebuild paths behind model actors, keep the UI-facing seams lightweight, and let the main actor go back to being a host instead of an accidental warehouse clerk.

The useful lesson: SwiftData is happiest when relationships are real, query scope is explicit, and cleanup logic works with the graph instead of around it. If the app keeps reaching for raw string scope and whole-table fetches out of habit, the database will still compile and still quietly charge interest later.

## Destructive Cleanup Honesty Pass: Either Commit Or Put The Chairs Back

This bug was a sneaky one because the scary part was not just the delete itself, it was the lie after the delete. `HomeTabView` was running logout cleanup inline, deleting multiple SwiftData buckets, then trying one `save()`. If that save failed, the app told the user “Nothing was changed,” even though the live `ModelContext` could still be sitting there with pending deletions like a restaurant after closing time: chairs on tables, floor half-mopped, cash drawer open, and someone insisting the room was untouched.

- The fix started with a small rule that now has teeth: destructive SwiftData mutations must either commit or explicitly `rollback()`. We added a shared `ModelContext.performRollbackSafeMutation` helper and pushed the logout delete sequence behind `LogoutCleanupService` instead of letting the view orchestrate the teardown itself.
- Privacy reset needed a slightly more nuanced contract. That flow mixes transactional SwiftData deletions with irreversible side effects like cache clearing and AuraPlay persistence cleanup. So we split it into two phases: first the transactional SwiftData reset that can roll back cleanly, then the follow-on cache/store cleanup that may only be able to report partial completion honestly.
- Account removal got pulled into the same discipline. The account store already owned the mutation boundary, but now overwrite/remove paths also use the rollback-safe helper so a failed destructive save does not leave the live context in a half-deleted ghost state.

The lesson: destructive flows need truthfulness as much as they need deletion logic. “Nothing changed” is only acceptable if the code can actually prove it put every chair back where it found it.

## Undo Support Reality Check: A Steering Wheel Needs A Rack

This one was a classic “the dashboard said we had a feature” problem. The app had an `UndoManager` attached to the primary SwiftData context, and destructive UI existed for playlists, account removal, and logout. That sounds like undo support right up until you read Apple’s contract: SwiftData only wires automatic undo when the scene or view uses `.modelContainer(..., isUndoEnabled: true)`. In other words, we had a steering wheel bolted to the dashboard, but not actually connected to the rack.

- The first fix was structural. We pulled the primary schema into one shared `PrimaryStoreSchema` definition and changed `AuralisApp` to install the container through SwiftUI’s `modelContainer(..., isUndoEnabled: true)` scene modifier. The app still keeps its “persistent store failed, fall back to in-memory” honesty, but now the normal production path is using the actual SwiftData undo seam instead of a hand-waved approximation.
- The second fix was transactional. Playlist deletes now run inside an explicit undoable mutation with a named action, so the user-facing destructive path maps to one coherent undo unit instead of a pile of side effects that happen to share a timestamp.
- Account removal had a subtler trap: it was deleting through a model-actor context, and Apple’s undo support only tracks saves on the main context. So we moved the destructive account-removal path onto the main context for that action, kept rollback protection, and let SwiftData finally record the deletion in a place the undo manager can see.
- We also added a full-schema in-memory test container for integrity checks. That let us write the tests that actually matter here: playlist delete can be undone, account removal can be undone, and rollback-safe delete helpers really do put the records back when a mutation blows up mid-flight.

The lesson: “has an undo manager” and “supports undo” are not synonyms. On Apple platforms, undo is plumbing. If the pipe is connected to the wrong context, the faucet is decorative.

## Destructive Flow Completion Pass: Stop Leaving Side Doors Unlatched

The first hardening pass fixed the obvious shell-level demolition jobs, but it left a few side doors unlocked: playlist deletion still rode through a convenience extension, AuraPlay reset still did multi-step deletes without rollback wrapping, and a handful of lower-level stores were still using the old “delete a bunch of rows and hope `save()` lands” pattern.

- We closed the playlist gap by introducing an explicit `PlaylistDeletionService` for the user-facing delete path. That means the swipe-to-delete UI now goes through a named destructive boundary instead of calling a model-context helper directly and pretending that was architecture.
- We also finished the plumbing underneath. Token holdings clear-all, search-history clear/remove, receipt reset, and live AuraPlay persistence reset now all use the same rollback-safe mutation helper. The point is not ceremony; the point is that a failed destructive save should leave the room in the same shape it found it.
- The actor-side playlist deletion helper was tightened too. It still exists for non-UI callers, but it now uses transactional rollback semantics instead of raw `delete + save`.
- The practical test story improved as well. The undo coverage now exercises the playlist deletion service and the account-removal undo path against a full primary-store schema container, while the existing privacy/reset tests continue checking rollback-versus-partial-completion behavior.

The lesson: consistency matters more than hero fixes. A codebase is not “safe” because the biggest wrecking ball got guard rails if the smaller wrecking balls are still parked on a slope.

## ARCH-001, First Cut: Take The Master Key Away From The Lobby

This was the first real implementation slice of the `ShellServiceHub` cleanup, and the most important decision was restraint. The goal was not “delete the hub everywhere in one dramatic swing.” The goal was “break the worst dependency direction first without turning the shell into a rubble pile.”

- `MainAuraView` stopped carrying the raw service locator and now takes `ShellBootstrapDependencies` instead. That means the shell entry point still knows how to bootstrap the app, but it no longer casually exposes the whole boiler room to the rest of the UI.
- `ShellStore.live(...)` also lost its `ShellServiceHub` dependency. It now takes a `ShellStoreDependencies` bundle with the exact collaborators it uses: selection persistence, account mutation, refresh coordination, deep-link replay, router effects, receipt logging, and the clock. That is a much more honest reducer boundary.
- `GatewayView`, `MainTabView`, `HomeTabView`, `ProfileDetailView`, and `SettingsView` were trimmed down to the narrower closures or feature bundles they actually consume. In practice, this meant passing things like `accountStoreFactory`, `privacyResetServiceFactory`, or `policyActionHandlerFactory` directly instead of letting views rummage through a global bag of unrelated parts.

The fun bug in this pass was predictable in hindsight: `HomeTabView` still had one secret tunnel back to the old world through logout cleanup. This is exactly how service locator migrations try to cheat. You remove the obvious bag from the initializer, and one last side-effect path is still quietly asking the bag for a wrench in the basement. The fix was to thread `logoutCleanupServiceFactory` through the home feature explicitly and close that side door too.

The last cleanup step was the one that actually makes the ADR feel finished instead of merely “less embarrassing.” `ShellServiceHub` is now private to `AppServices.swift`, and the old boundary tests were replaced with builder-focused tests for shell bootstrap, gateway wiring, main-tab feature wiring, policy gates, and privacy reset. That matters because an architecture migration is not complete when the UI stops touching the old type. It is complete when the old type also stops being a public idea the rest of the codebase can casually re-adopt next Tuesday.

The lesson is delightfully unromantic: architecture migrations get safer the moment you stop trying to be impressive. One well-placed cut at the composition boundary beats a heroic “we replaced DI across the whole app in one diff” story every time.

## ARCH-001 Test Hardening: Audit The Plumbing, Not The Paint

Once the first DI migration cut landed, the obvious next question was whether the test story had actually caught up or whether we had just traded one architectural smell for a very confident shrug. The existing builder tests proved that some live seams still connected to the right stores, but they did not really interrogate the shell state machine itself. That is like checking that the restaurant has a pantry, a stove, and a fridge, while never confirming whether the kitchen staff can still get dinner onto the table in the right order.

- The fix was to add a dedicated `ShellStoreTests` suite that stays completely out of SwiftUI. No view snapshots, no navigation rendering, no “the tab looked roughly fine in Preview.” Just the shell reducer, its collaborators, and the behaviors this migration was supposed to protect.
- The new tests cover the moments where DI architecture either earns its keep or gets exposed as decorative paperwork: restoring persisted selection, repairing bad persisted chain scope from the account record, switching accounts with route resets, persisting chain changes, replaying deep links only when the shell is ready, refreshing stale selections on foreground, and clearing everything cleanly on logout.
- The important engineering choice was fake design. Each collaborator got its own tiny test double with one job: remember what it was asked to do. That keeps the tests readable and avoids the usual service-locator trap where the test setup quietly recreates the same giant bag of mystery wires that production just got rid of.
- There was also a nice little concurrency reminder hiding in the refresh path. `ShellStore` starts refresh work in tasks, so the test suite had to assert the reducer effects after yielding just enough for queued work to settle. Not because we enjoy making async tests harder than they need to be, but because state machines that spawn work need tests that understand when the dominoes are synchronous and when they are politely scheduled for one beat later.

The lesson: when a refactor claims to improve dependency boundaries, the best tests are not the ones that admire the new initializer signatures. The best tests are the ones that force the state machine to drive through every sharp turn and prove the new seams still hold the car together.

## ARCH-002 Boundary Call: Keep Persistence Translation In The Persistence Room

This was one of those architecture questions that sounds small until you realize it decides which type quietly starts collecting everyone else’s chores.

- The question was whether `PrepareNFTMetadataUseCase` should go one step further and manufacture persistence snapshots, or whether `PersistNFTInventoryUseCase` should own that translation. We chose the second option on purpose.
- The clean seam is now explicit: fetch provider inventory, prepare canonical domain inventory, then persist with persistence-owned translation. That means metadata prep gets to stay a domain-shaping step instead of gradually turning into a secret SwiftData adapter wearing a friendlier name.
- This matters because snapshots are not neutral packaging. They usually encode merge keys, local-state carry-forward rules, stale-cleanup inputs, write ordering, and other storage-specific invariants. Once that logic leaks upstream, the “prepare” layer stops being reusable and starts dragging persistence policy around like glitter on a sweater.
- We also locked the pragmatic naming decision for the first PR: keep the shell-facing type named `NFTService`. First earn the architectural separation, then decide later whether the honest final public name should become `NFTRefreshCoordinator`.

The lesson is classic boundary hygiene: if a value mostly exists to help storage make promises, let the storage-side use case own it. Otherwise the domain layer becomes a polite-smelling basement full of persistence boxes.

## Legacy Music Deletion Recon: The "Old Music App" Is Smaller Than It Was, But Wider Than It Looks

This pass was documentation work, but the useful part was not the markdown. The useful part was forcing the repo to answer a very specific question honestly: what exactly is still "old music" if the goal is to delete everything that is not AuraPlay?

- The first answer was pleasantly boring. There is no `MusicApp/OLD/` wing left to bulldoze. That ghost was already exorcised.
- The second answer was the real one. The legacy surface is still very alive under `MusicApp/AI/V1/`, but it also leaks into the shipping app through shell routes, the bottom mini player, the full-screen now-playing view, the legacy fallback stage in `AuraPlayTabRootView`, and a handful of shared AI-era types that AuraPlay still imports as bridge infrastructure.
- The most important gotcha was playback ownership. `AudioEngine` may feel like generic plumbing now, but in this repo it still lives under the old AI music path and AuraPlay still talks to it through adapter seams. Deleting the old music app cleanly therefore means either re-homing that engine into AuraPlay or replacing it, not just pretending folder names are architecture.
- The sneakiest dependency was `Playlist`. It looks like old library UI furniture, but the current audio engine still uses `Playlist(name: "Previous")` and `Playlist(name: "Next")` as in-memory queue containers. That is the kind of dependency that turns "simple cleanup" into "why did playback explode?" if nobody writes it down first.
- The old library bridge has the same problem in a different costume. `MusicLibraryIndex.swift` still defines `MusicLibraryItem` and the `MusicLibraryIndexing` seam, and AuraPlay still falls back to that layer when its own persisted graph is not the authority yet. So removing the legacy music experience for real also means deleting the fallback mindset, not just the visible old screens.

The new runbook lives at `Auralis/Auralis/docs/plans/AuraPlay/AuraPlay-Legacy-Music-Removal-Runbook.md`, and its main lesson is simple: repo archaeology beats confidence. Old product surfaces rarely die in one folder. They die in routes, schemas, adapters, cleanup code, tests, and the one "temporary" bridge everyone forgot was still load-bearing.

One important decision got clarified immediately after that audit: `AudioEngine` is not being grandfathered in as a blessed survivor. The plan is to empty `MusicApp/AI/Audio Engine/` out and move detail routing plus the mini-player path fully into AuraPlay. That is the right kind of ruthlessness. Otherwise you do not really delete the old music app; you just give it a fake mustache and let it keep living in the crawlspace.

## AP-SYS-005 Planning Pass: Music Receipts Stop Being Background Noise

This planning pass was a useful reminder that “receipt” and “log line” are cousins, not twins. Logs are what the app mutters to itself in the back room. Receipts are what it should be willing to say out loud later when Mission Control asks, “what exactly happened here?”

- The first important discovery was that the receipt plumbing is already real and reusable. `StoredReceipt`, `SwiftDataReceiptStore`, `ReceiptEventLogger`, and the timeline/detail views already give us the filing cabinet. Music does not need a second cabinet with “special audio papers” scribbled on the front.
- The second discovery was that the active music code is split like a house with a new kitchen and an old furnace. `AuraPlay/` is the current product-facing shell, but `AI/Audio Engine/` still owns the concrete playback and playlist mutation seams. That means playlist receipts belong down in the mutation layer, not in some shiny SwiftUI button that only happens to call it today.
- The third lesson was about honesty under pressure. `AudioEngine` already has cancellation and auto-advance logic, which means playback receipts can lie very easily if they fire too early. A cancelled load is not “playback started.” A superseded track is not “playback completed.” The plan locks that down before implementation gets clever.
- There was also a surprisingly practical architecture choice around actors. The ticket asks for `user`, `system`, `operator`, and `plugin`, but the app’s top-level receipt actor model is still just `user` or `system`. Instead of widening global types for one ticket, the better move is the same trick used in external-link receipts: keep the coarse top-level actor, then use payload and provenance to tell the sharper story.

The memorable bit: music receipts are not there to make the app sound busy. They are there so the app can testify later without improvising.

## AP-SYS-005 Status Pass: The Repo Already Built Half The Bridge

This was a good old-fashioned documentation reality check. The plan file was still talking like the band had not shown up yet, while the repo was already halfway through soundcheck.

- The first useful discovery was that the “future architecture” from the planning doc is no longer future. `MusicReceiptEventType`, `MusicReceiptPayloads`, `MusicReceiptEventLogger`, and even a dry-run auto-organization service already exist. In other words, the blueprint was still warning us to pour the foundation while the studs and wiring were already in the walls.
- The second discovery was more important than the first: implemented is not the same thing as shipped. Playlist receipts are wired into the real persistence seam. Policy-block receipts are wired into the existing gate. Playback and queue receipts are wired into `AudioEngine`. But the auto-organization dry run still looks like a well-built stage prop unless a real product path actually calls it.
- The third lesson was about verification humility. The app builds cleanly, which is worth something. But the targeted music receipt tests came back from the Xcode runner as `No result`, which is the testing equivalent of a witness shrugging and saying, “I was definitely at the scene, but I did not actually see anything.” That means the status doc had to say “incomplete verification” plainly instead of playing lawyer with the wording.
- The sneaky architecture lesson is that stale planning docs are not harmless. Once a strategy file claims types are missing when they already exist, it stops being guidance and starts being a trap. The next engineer can waste time building a second bridge right next to the first one just because the map forgot to update.

The sticky takeaway: codebases age like cities, not spreadsheets. If you want the truth, do not just read the zoning document. Walk the streets and see which buildings are already standing.

## SEC-006 Follow-Through: Confirmation Is The Lock, Logging Is The Clipboard

This security pass had a subtle contract question hiding inside a reasonable-sounding review comment: if receipt logging fails, should the confirmed Safari handoff fail too?

- We kept the hard boundary in the right place. The meaningful security gate is the second user action, not the receipt write. If the user explicitly reviews the destination and taps `Open in Safari`, the app should honor that choice even if the audit trail has a bad day.
- The implementation now says that plainly in code instead of mumbling it through `try?`. `ExternalLinkOpenFlow` still attempts receipt logging first, but logging is best-effort and the confirmed handoff proceeds either way.
- The testing strategy also got more honest. We are not pretending to have UI coverage we did not write. Instead, the unit suites now do more of the useful heavy lifting: policy coverage expands across every supported explorer host plus the approved IPFS gateways and Arweave host, and the flow tests now pin the “logging failure does not block a confirmed open” rule directly.

The lesson is a good one to keep around: security boundaries and observability boundaries are not the same thing. The lock on the door is the explicit confirmation step. The clipboard is the receipt log. Important? Yes. The same thing? Absolutely not.

## SEC-006 Cleanup Pass: Reusable Means Not Smuggling Newsfeed Types Into App-Level Helpers

The first SEC-006 pass got the behavior right, but it left a small architectural banana peel on the floor. `ExternalLinkPolicy` was supposed to be app-level and reusable, yet it still accepted `NFTExternalDestination`, a tiny type declared inside `OpenSeaLink.swift`. That is the software equivalent of building a good city water main and then routing it through one specific coffee shop’s basement.

- The fix was intentionally boring: promote the candidate URL model into the helper layer as `ExternalLinkCandidateDestination`, then point the NFT-detail buttons and policy tests at that shared type.
- The important part is not the rename. The important part is that future artwork, audio, IPFS, Arweave, or settings-link call sites can now use the confirmation policy without importing a Newsfeed component just to carry a `label` and a `url`.
- This is one of those senior-engineer cleanup moves that does not change the demo, but it changes whether the next feature arrives as a clean extension or as a “why does Settings depend on NFT detail?” incident report.

The sticky lesson: reusable abstractions are not reusable if their input types are hiding in a product leaf node wearing fake glasses.
