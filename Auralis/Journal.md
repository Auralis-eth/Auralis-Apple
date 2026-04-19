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
