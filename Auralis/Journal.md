# Journal

## The Big Picture

Auralis is what you get if a wallet tracker, an NFT browser, a receipts notebook, and a music player all agreed to share one apartment. You bring a wallet address to the front door, the app pulls in what it can see on-chain, stores the useful pieces locally, and then lets you explore that world through Home, News, Tokens, Receipts, and Music. The vibe is not "crypto terminal." It is more like "ambient dashboard with a long memory."

## Architecture Deep Dive

The app shell behaves like the front desk at a busy hotel. `MainAuraView` and the mounted shell decide who is checked in, which chain they are looking at, and which service needs to answer the next question. `NFTService` and `NFTFetcher` are the delivery crew bringing in inventory from providers, while SwiftData is the storeroom where the app keeps the parts it wants to reuse without asking the network every five seconds.

The audio stack is its own little stage crew. `AudioEngine` keeps the playback machinery alive across screens so the music UI can act more like a remote control than a disposable toy. Receipts are the black box recorder: when important things happen, the app writes down what happened, where it happened, and enough surrounding context to explain it later without dumping raw sensitive values all over the floor.

## The Codebase Map

- `Auralis/Aura/`: shell, tabs, auth, Home, search, newsfeed, and shared visual primitives
- `Auralis/Accounts/`: account persistence and holdings state
- `Auralis/DataModels/`: SwiftData-backed models and domain types
- `Auralis/Networking/`: provider seams, fetchers, caches, retry logic, and config
- `Auralis/Receipts/`: receipt schema, stores, reset, and sanitization
- `Auralis/MusicApp/AI/`: active music UI and audio engine
- `Auralis/MusicApp/OLD/`: the attic; interesting, but not where the current player lives

## Tech Stack & Why

SwiftUI is doing the UI heavy lifting because the app is fundamentally state-driven and needs the shell to react cleanly to account, chain, and loading-state changes. SwiftData is the local pantry because this app needs durable scoped storage for NFTs, holdings, receipts, and account metadata without building a custom database story from scratch. Swift Concurrency fits the networking and media flows because cancellation, retry, and long-lived tasks are normal here, not exotic.

The provider layer exists because direct provider code in views would turn the app into wet cement. The receipt system exists because once you have multiple surfaces sharing identity and state, "why did this happen?" stops being a nice-to-have and becomes table stakes.

## The Journey

### New move: turning Phase 0 into something another engineer can actually inherit

One quiet failure mode in app projects is "the code works, but the next person has to become a detective." Phase 0 had reached the point where implementation-order docs and ticket closeout notes existed, but they still assumed the reader was willing to play archaeological dig across dozens of files.

The fix was to add four operating documents with distinct jobs instead of one giant sludge file:

- `LLM_CONTEXT.md` for the compressed mental model of the app
- `P0-Future-Work.md` for what actually matters next
- `P0-Physical-Device-QA-Suite.md` for real-device validation of P0
- `P0-UI-Design-Audit-Checklist.md` for product/design review of P0

That matters because Phase 0 is not "done forever." It is more like finishing the foundation and then taping labels onto the breaker box so the next engineer does not shut off the house by accident.

### War story: release-readiness is where the loose floorboards show up

The `P0-802` and `P0-803` pass was less about adding shiny UI and more about turning hand-wavy confidence into explicit artifacts. Performance baselines are easy to fake by saying "it feels okay." Security checklists are easy to fake by saying "we should review that later." Both are useless if the next engineer cannot tell what was actually checked.

The fix was documentation with teeth:

- `P0-802-Baseline-Report.md` now defines the first two benchmark flows that matter: address-entry-to-shell and opening the ERC-20 surface.
- `P0-803-Privacy-Security-Checklist.md` now names the active surfaces that were reviewed and the hardening that is still deferred.

### Aha moment

The app already had more privacy discipline than it first appeared. Receipt sanitization, scoped search history, validation-first account entry, and explicit trust labels were all there in pieces. The problem was not "nothing exists." The problem was "the evidence was scattered across the building like receipts in different jacket pockets."

### New move: settings as the control room, not a junk drawer

The latest `P0-803` follow-on turned that scattered privacy work into something a real user can actually operate. A settings page now exists under Profile, and it does two useful things instead of ten decorative things:

- it shows whether the single shipped Alchemy key was injected into `Info.plist` at build time through xcconfig
- it exposes one privacy reset that clears receipts, search history, ENS cache, gas cache, and token-holdings cache in one shot

That sounds small, but it fixes a classic app problem: all the safety seams existed, yet nobody had built the dashboard to drive them.

### New move: receipts stop trusting mystery strings

The next hardening pass taught the receipt system a better habit. Instead of tossing loose dictionaries over the wall and hoping the sanitizer guesses which strings are dangerous, the active receipt emitters now describe each field with intent: public, redact, hash, truncate. That is much closer to how grown-up audit logs behave.

The practical result:

- URLs are sanitized structurally instead of only being hidden when the key happens to be named `url`
- wallet addresses are hashed or masked deliberately
- copied text and raw errors stop pretending to be harmless metadata
- unknown strings default to suspicious until a payload builder classifies them

### New move: one real shipped key means one real runtime dependency

The provider configuration story also got less theatrical. The app no longer pretends it has a whole bag of optional provider secrets. Runtime configuration is now `Info.plist`-only, populated through xcconfig, and release builds fail immediately if the Alchemy key is missing. Gas pricing was moved off the old Infura-shaped dependency path and onto the shared Alchemy RPC seam, which means the build now depends on one actual key instead of a secret-management hydra.

Then came the classic Xcode booby trap: the project had xcconfig wiring for `INFOPLIST_KEY_AURALIS_ALCHEMY_API_KEY`, the local secret file existed, and the app still launched with `rawPresent=false`. In other words, the pipe was "configured" in theory but dry in practice. The pragmatic fix was to stop being coy and add `AURALIS_ALCHEMY_API_KEY` directly to `Info.plist` with the `$(AURALIS_ALCHEMY_API_KEY)` build-setting placeholder. Same secret source, less magic, fewer haunted-house debugging sessions.

The next trap was more subtle: once the key worked, Alchemy itself started returning HTTP 500 for a real wallet on `getNFTsForOwner`. That is the kind of failure that can waste a lot of time if the app treats every provider error like flaky Wi‑Fi. The better move was to degrade the request shape inside the provider client: if the rich metadata request explodes, retry once with a lighter owner fetch and stop the outer fetcher from hammering the same 500 ten times in a row.

Then the provider did one more annoying but very realistic thing: the degraded response shape stopped including `contract` for some NFTs. The app was decoding that field as mandatory, which turned one ugly page into a full retry storm. The repair was not glamorous; it was correct. `NFT` and `Contract` now decode missing contract data defensively, and `NFTFetcher` treats `DecodingError` like a schema problem instead of cosplay network turbulence.

That fix had a sequel. The first fallback implementation used `Contract(address: nil)`, which looked harmless until SwiftData reminded us that `Contract.id` is unique. A whole page of "missing contract" NFTs all tried to become the same contract record, and persistence started throwing identity-remap failures like a database smoke alarm. The better move was to synthesize a per-item fallback contract identity from token metadata so degraded provider rows can still be saved without pretending they all share one phantom contract.

Then SwiftData pulled out one more rake from the grass. Even after contracts were fixed, the save path still blindly called `insert` on every fetched NFT, including items that already existed in the store or showed up twice in the same provider batch. That is how you get the unforgettable message about a `PersistentIdentifier` being remapped "to a temporary identifier during save," which is SwiftData's way of saying, "you tried to create a second version of the same person and now the seating chart is on fire." The cure was straightforward and important: dedupe the fetched batch by scoped NFT id, then upsert persisted rows in place instead of always inserting new ones.

The token URI path also got a much-needed volume knob. NFT metadata in the wild is a flea market, not a museum. Some tokens hand you `data:application/json;base64,...`, some hand you `data:image/svg+xml`, some point at `ar://`, and some are just weird. The parser now only base64-decodes URIs that actually claim to be embedded JSON, keeps known non-HTTP media schemes without yelling about them, and stops narrating every duplicate token URI like it has discovered a crime. The result is a log stream that highlights malformed data instead of normal NFT chaos.

One last provider lesson came from pagination. Falling back from a rich Alchemy request to a degraded one is not enough if the next page quietly switches back to the rich request and explodes all over again. That creates a tedious loop of `500 -> degrade -> next page -> 500 -> degrade`, which is technically resilient but operationally obnoxious. The fix was to make the fallback sticky for the lifetime of that refresh: once the provider proves it needs the lighter request shape, keep using it until the pagination run is over.

There was a quieter engineering lesson hiding behind all of this: debug logs should act like instrument panels, not slot machines. Per-page request dumps were useful while the fetch path was on fire, but once the bug was understood they mostly buried the signal under repetitive noise. The better steady-state policy is one summary line per refresh, explicit logs for non-2xx responses, and one clear note when the provider switches into degraded mode. That keeps the console readable when something breaks for real.

### Pitfalls worth remembering

- xcconfig-to-Info.plist injection is now the intended secret path, and release builds fail fast if required keys are missing.
- Search history and ENS cache now participate in one privacy reset, but receipt payload growth still needs ongoing review.
- Receipt sanitization is stronger now, but every new payload shape still needs deliberate sensitivity classification at the emitter.
- Audio temp files are cleaned up on active replacement paths, but lifecycle edge cases still deserve a focused review.
- If NFT loading suddenly looks dead on first launch, check the startup logs before blaming pagination or wallet parsing. In this app, `rawPresent=false` plus `nftURL=nil` is the smoking gun that the Alchemy key never made it from `Secrets.local.xcconfig` into `Info.plist`.
- If a provider fallback endpoint returns "valid enough" but thinner JSON, decoding rigidity becomes a product bug. Missing `contract` data should degrade identity quality, not trap the fetcher in ten retries and a fake loading hang.
- A test helper can turn into a security hole if its scope check is lazy. `Password.isRunningTests` used to return `true` for every `DEBUG` build, which quietly routed wallet-password storage into `UserDefaults` during ordinary development. The fix was simple and worth remembering: detect actual XCTest process markers, not build configuration. "Running debug" and "running tests" are cousins, not twins.
- The better follow-up was to delete the hidden mode switch entirely. `Password` now talks to an injected `PasswordStore`, with `PasswordStores.live` using Keychain and `PasswordStores.test(...)` using explicit `UserDefaults` fallback. That is the healthier shape: production security as the default, tests opting into their fake world on purpose instead of by horoscope.
- Receipts had their own version of "two clerks, one ticket machine." `ReceiptStores.live(modelContext:)` used to mint a fresh `SwiftDataReceiptStore` every time, and each store had its own local idea of the next sequence id. That works right up until two callers ask for a store at once and both decide the next number is, say, 41. The fix was to make the live receipt store and its sequence allocator shared per `ModelContext`, so sequence assignment has one authoritative memory instead of several polite impostors.
- ENS cache work got one of those small-but-real quality upgrades that saves everyone a little annoyance all day long. `ProfileCardView.refreshENSName()` used to say, "great, I found a verified cached ENS name... now let me hit the network anyway." That is the software equivalent of checking the fridge for milk, seeing the milk, and still driving to the store. The fix was cache-first behavior with a stale-aware fallback: fresh verified cache returns immediately, stale cache renders optimistically and refreshes in the background, and slow results are ignored if the viewed address has already changed.

## Engineer's Wisdom

Good engineers do not confuse "there is code" with "there is a contract." This codebase keeps getting better when ownership is explicit: shell state lives in the shell, providers stay behind seams, receipts sanitize before they persist, and views do not get to freeload on global knowledge they do not own.

Another recurring lesson: the safest path is usually the narrowest one. Read-only wallet watching is safer than pretending to be a signing wallet. Scoped local history is safer than global logs. Clear deferrals are safer than fake completeness.

One smaller but worthwhile cleanup came from the audio stack. The live `AudioEngine` had split remote loading across private helper layers, which made it too easy for playback-state transitions to live in one room while download failures happened in another. The better answer here was subtraction: collapse the helper chain back into the existing private `loadAndPlay` path so the loading state sits next to the work that can actually fail.

We also deleted the old `MusicApp/OLD/AudioPlayerManager.swift` file. It had no live callers and only one commented-out reference in another legacy file. Unused audio code is not a harmless keepsake; it is a future debugging detour waiting for a tired engineer.

## If I Were Starting Over...

I would establish the privacy reset story and the production secrets story earlier. Both are easier to design before a dozen surfaces accumulate their own little caches and local stores. I would also wire in a small automated benchmark harness sooner, because "we'll measure it later" is how performance work quietly becomes folklore.
