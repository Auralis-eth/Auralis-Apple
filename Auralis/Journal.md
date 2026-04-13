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

### Pitfalls worth remembering

- xcconfig-to-Info.plist injection is now the intended secret path, and release builds fail fast if required keys are missing.
- Search history and ENS cache now participate in one privacy reset, but receipt payload growth still needs ongoing review.
- Receipt sanitization is stronger now, but every new payload shape still needs deliberate sensitivity classification at the emitter.
- Audio temp files are cleaned up on active replacement paths, but lifecycle edge cases still deserve a focused review.

## Engineer's Wisdom

Good engineers do not confuse "there is code" with "there is a contract." This codebase keeps getting better when ownership is explicit: shell state lives in the shell, providers stay behind seams, receipts sanitize before they persist, and views do not get to freeload on global knowledge they do not own.

Another recurring lesson: the safest path is usually the narrowest one. Read-only wallet watching is safer than pretending to be a signing wallet. Scoped local history is safer than global logs. Clear deferrals are safer than fake completeness.

## If I Were Starting Over...

I would establish the privacy reset story and the production secrets story earlier. Both are easier to design before a dozen surfaces accumulate their own little caches and local stores. I would also wire in a small automated benchmark harness sooner, because "we'll measure it later" is how performance work quietly becomes folklore.
