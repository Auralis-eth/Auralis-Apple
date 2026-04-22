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

- Image loading hardening: this was a good example of the difference between “an issue was reported” and “the issue is real.” Some of the checklist items were stale on arrival, but two image-loader bugs were absolutely real. `ImageLoader` could fall into a permanent-looking error state after one transient network miss because the view had no in-place retry path, and oversized payloads were being funneled through `try?` into the same bland `.invalidData` bucket. The fix was intentionally surgical: add a retry affordance only for retryable network failures, preserve the explicit oversized-file failure mode, and lock the related tests to serialized execution so the shared URLProtocol mock stopped sabotaging its own evidence.

- Pinned-actions corruption handling: `HomePinnedItemsStore` had a classic “recovery” bug that was really a data shredder in a polite hat. If stored pinned-item JSON became corrupted, read paths logged the decode failure and returned `[]`, which was tolerable for display, but the next toggle write would happily overwrite the bad blob with a fresh array and make the old state unrecoverable. The mutating path now fails closed with a real store error instead of treating corruption as an empty set. That is the safer engineering instinct: when local state smells wrong, do not casually rewrite history.

- Another pre-ship review pass had a similar theme: some scary-looking checklist items were stale, and some were absolutely worth fixing. `NSCameraUsageDescription` was already present, and the privacy-manifest worry around `CryptoKit` hashing turned out to be a false alarm after checking Apple’s current required-reason API categories. But `GuestPassCard` really did run a perpetual shimmer with no Reduce Motion escape hatch, so the card now respects `accessibilityReduceMotion` instead of insisting every user wants the same amount of motion. That is one of those bugs that can hide in plain sight because the animation looks “nice” right up until it makes someone feel awful.

- The loading surface got a small but important copy cleanup too. `NFTNewsfeedLoadingView` was speaking fluent developer status message: “Fetched X NFTs. Parsing metadata before save.” Technically true, product-wise clunky. The wording now sounds like an app talking to a person instead of a progress log talking to another progress log.

- The receipts timeline also got a render-path cleanup. `ReceiptsRootView` was rebuilding its decoded receipt records and filtered snapshot straight from `body`, which is exactly the kind of thing that works fine until a timeline gets large and SwiftUI starts asking for fresh values more often than you expected. The decoded snapshot is now refreshed from a keyed task into local state, so the view body mostly consumes prepared data instead of doing all the sorting and filtering work inline.

- One more small polish fix landed in the external NFT links. The OpenSea and explorer buttons were using hardcoded hex gradients, which is a fast way to get a button that looks “branded” in one context and weirdly out of place in another. Those buttons now lean on semantic app colors instead of frozen hex values.

- Networking hardening pass: this one was a good example of how “works on a sunny day” is not the same thing as “ship-ready.” The ERC-20 provider had pagination loops that trusted the backend like an overly optimistic intern. One repeated cursor or one endless stream of empty pages and the sync could hang forever. We added explicit stall detection, then taught the provider to admit when enrichment metadata failed instead of quietly serving placeholder rows with a fake smile.

- The RPC path got the same reality check. Native balance loading used `URLSession.shared`, took one swing, and if it missed, `ContextService` basically shrugged and erased the balance from the snapshot. That is not resilience; that is amnesia. The provider now has explicit timeout and retry policy, `ContextService` reuses the last balance for the same wallet/chain scope on refresh failure, and both RPC clients now read JSON-RPC error envelopes instead of pretending every HTTP 200 is a happy ending.

- Another useful lesson from this round: test fallout is often the most honest reviewer in the room. Changing `tokenHoldings(...)` from “array only” to “holdings plus warning” immediately surfaced every place the repo had quietly encoded the old contract. Fixing those tests was not bookkeeping; it was the proof that the new behavior was actually wired end to end.

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

- `NFTMetadataUpdater` now knows how to build a pure metadata patch as a sendable value.
- `NFTService` snapshots only the raw metadata inputs it needs, computes those patches in a detached task, then comes back to the main actor to apply the results to SwiftData-backed `NFT` objects.
- cleanup failure receipts were also corrected to use the known requested account and chain instead of reverse-engineering scope from whatever stale NFT array happened to be around after a failure.

This is one of those engineering moves that feels a bit like moving a kitchen remodel into the garage so dinner service can keep running. The heavy chopping and prep happen off to the side; the final plating still happens where the real dishes live.

The practical lesson: if a model object is actor-bound, do not try to brute-force it across concurrency boundaries. Extract the pure inputs, do the expensive interpretation elsewhere, then apply the result back at the ownership boundary. That pattern is safer, easier to explain in code review, and much less likely to produce the kind of “it builds, but now persistence is haunted” regression that ruins a Friday.

### Small Defects, Real Consequences

This cleanup round was not glamorous, but it was exactly the sort of work that keeps a release from feeling sloppy.

- `HomeTabView.logout()` used to shrug at SwiftData deletion failures with `try?`. That is the software equivalent of dropping the office keys down a storm drain and marking the task complete. Logout now fails explicitly: if local cleanup throws, we log it, show the user an error, and stop instead of pretending state reset succeeded.
- `AppDeepLinkParser` was passing a token-only chain requirement through receipt routes. Nothing exploded, but it was a logic smell: a receipt route was carrying a backpack full of token assumptions it never used. That requirement is now removed for receipts so the parser says what it means.
- two production error logs were printing wallet addresses as public values during chain-selection persistence failures. Not a crash, but definitely not the kind of observability gift you want to hand over in release logs. Those addresses are now hashed in logs instead.

The lesson is that defect resolution is not always about dramatic stack traces. Sometimes it is about refusing to let “quietly wrong” stay quiet: hidden logout failures, misleading parser wiring, or logs that leak more than they should. That is how a codebase gradually stops surprising you in production.

## Engineer's Wisdom

- Dead code removal is only “safe” after verifying inbound references and then building the project. Grep without validation is guesswork.
- Large files attract unrelated responsibilities over time. That is how you end up with domain models living next to abandoned UI experiments.
- The cleanest architecture in the world still loses clarity if old view stacks are left behind after a routing refactor.
- A senior-engineer move here is to treat code archaeology as part of product quality, not as a cosmetic chore.
- SwiftUI performance problems often look tiny in code review. A single formatter in a computed property, one `Data(contentsOf:)`, or one array filter in `body` can seem harmless until it sits on a path that re-renders constantly.
- If a control looks tappable, it should usually be a `Button`. Accessibility is much easier when semantics and visuals are aligned instead of retrofitted later.
- But the inverse also matters: if a region contains other controls, making the whole thing a `Button` can create an interaction turf war. One tap target per job keeps the peace.
- Derived data from `@Query` should stay derived unless you have a strong invalidation story. Caching without complete invalidation rules is just a polite form of lying.

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
