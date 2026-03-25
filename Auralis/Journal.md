# Journal

## The Big Picture

Auralis is the kind of app you build when a wallet, an NFT gallery, a dashboard, receipts, and a music player all decide to share one apartment. The job is not just "show some tokens." The app has to remember who the user is watching, pull on-chain data without acting brittle, keep a local memory of what matters, and make the whole thing feel like one coherent product instead of five roommates fighting over the kitchen.

## Architecture Deep Dive

The architecture is trending toward a clean "front desk and back office" split.

`MainAuraView` is the front desk. It decides who is checked in, what chain context is active, and which major surface the user is looking at.

The services are the back office. `AccountStore` handles identity persistence. Provider-backed networking handles remote reads. Receipt logging is the security camera that keeps a trail of what happened. SwiftData is the filing cabinet. When this setup is healthy, views ask for outcomes and state, not for raw RPC tricks.

The latest example is ENS planning. The temptation is to let the first working library or provider API leak all over the app. That is how architecture quietly turns into wet cardboard. The better move is to put an `ENSResolving` seam in front of the first implementation so the app talks to "resolve this identity" while the backend can start with Argent's `web3.swift` and later swap to direct Ethereum RPC or a lighter node strategy.

## The Codebase Map

The current city map looks like this:

- `Auralis/Auralis/Aura/` is the product shell and user-facing SwiftUI surfaces.
- `Auralis/Auralis/Accounts/` is the identity desk for watch-only accounts and account event seams.
- `Auralis/Auralis/Networking/` is where provider abstractions, fetchers, throttling, and remote reads live.
- `Auralis/Auralis/Receipts/` is the audit trail.
- `Auralis/Auralis/DataModels/` is the domain and persistence layer.
- `Auralis/Auralis/MusicApp/AI/` is the active music path. `OLD/` is the code equivalent of a museum wing: interesting, but not where you should start changing behavior.

## Tech Stack & Why

SwiftUI is doing the heavy lifting for UI because the app is stateful and cross-surface. SwiftData is the local memory because identities, NFTs, and receipts need durable storage without building a custom database story in Phase 0. Async/await is the right fit because networking, refresh, cancellation, and stale-state behavior are first-class concerns here.

Provider abstraction matters because this app already talks to more than one external backend. The real lesson is not "pick one provider forever." It is "never let the first provider become the shape of the whole app."

## The Journey

### War Story: ENS Planning Needed A Backbone Before It Needed Code

`P0-203` looked simple on the surface: resolve ENS names and do reverse lookup. The trap was that there were three plausible paths:

- use the installed Argent `web3.swift` package
- hand-roll direct RPC
- find a provider shortcut that was not really there

The inspection cut through the fog fast. The repo has a real Alchemy provider seam and a real Infura gas client, but ENS itself is not implemented anywhere in app code. The package source told the real story: Argent's `web3.swift` already ships `EthereumNameService`, resolver lookups, reverse resolution, wildcard support, and offchain lookup support.

That led to the decision:

- ship `P0-203` with `web3.swift` first
- put it behind a provider-agnostic ENS service seam
- preserve a future backend swap to direct Ethereum RPC or a lighter node path

That is the kind of decision good engineers make when they want velocity today without writing tomorrow's migration bug report.

### War Story: The ENS Race That Could Have Time-Traveled a User Into the Wrong Wallet

The first ENS slice had the classic async UI bug: every submit launched a fresh task, but nothing stopped an older, slower lookup from arriving late and acting like it was still the chosen input. That is how a user types one ENS name, quickly changes to another, and gets checked into the wrong account because the network answered out of order. Software time travel is funny only when it is not your auth flow.

The fix was deliberately boring in the best way:

- cancel the previous submit task before starting a new one
- stamp each request with a submission ID
- allow only the latest submission to mutate UI state or persist an account

`P0-203` also had a quieter trap. If a cached ENS name used to point at one address and now pointed at another, the app would log a mapping-change receipt but still barrel ahead and save the new address. That is not "awareness." That is silent drift with a paper trail.

The safer behavior now is:

- surface the mapping change as a real app-level ENS error
- keep the old cached mapping in place until the user explicitly confirms the new address
- let the gateway show a confirmation alert instead of treating the new mapping as automatically trusted

The receipts story also graduated from hope to proof. The code already emitted cache-hit, start, success, mapping-change, and failure events, but there were no tests proving the recorder actually wrote the right sanitized payloads. A focused receipt test now exercises that full sequence so future regressions have somewhere concrete to crash.

## Engineer's Wisdom

A senior engineer does not ask only "what works?" They ask "what will this force the rest of the codebase to believe?"

If views start depending on Alchemy-shaped ENS models, you did not just solve ENS. You taught the entire app a vendor dialect. That always feels cheap in the moment and expensive a month later.

The better pattern is:

- define the app-facing contract first
- isolate the provider-specific adapter behind it
- make caching and receipt semantics belong to the app, not to the vendor

## If I Were Starting Over...

I would establish more provider-agnostic service seams earlier, especially around identity-like data such as balances, ENS, and token metadata. Those are exactly the places where "just call the provider directly for now" grows teeth later.

The saving grace is that the codebase is still early enough to correct course while the concrete is wet instead of after the building inspection.
