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

- Provider startup and retry behavior got a realism upgrade too. `AuralisApp` was using `preconditionFailure` when provider configuration was missing, which is fine if your app is a unit test and less fine if it is a shipped product. Launch now degrades instead of detonating. On the fetch side, `NFTFetcher` had retry machinery but still refused to retry provider 5xx failures and generic HTTP server errors, which is like installing a backup generator and then deciding not to use it during an actual outage. The retry policy now gives transient server-side failures another chance, which is much closer to the resilience story the surrounding code was already trying to tell.

- Image loading hardening: this was a good example of the difference between “an issue was reported” and “the issue is real.” Some of the checklist items were stale on arrival, but two image-loader bugs were absolutely real. `ImageLoader` could fall into a permanent-looking error state after one transient network miss because the view had no in-place retry path, and oversized payloads were being funneled through `try?` into the same bland `.invalidData` bucket. The fix was intentionally surgical: add a retry affordance only for retryable network failures, preserve the explicit oversized-file failure mode, and lock the related tests to serialized execution so the shared URLProtocol mock stopped sabotaging its own evidence.

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
