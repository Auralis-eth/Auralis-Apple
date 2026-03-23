# Journal

## The Big Picture

Auralis is trying to be the polite, read-only operating system for wallet-based NFT browsing. Not a trading terminal. Not a signing wallet. More like a museum guide with a clipboard: it knows who you are watching, what chain you care about, what it last fetched, and it keeps receipts for what happened.

This session was less "ship a shiny new feature" and more "walk through the house with a flashlight and see which doors are real and which ones are painted on the wall." The result: some Phase 0 work is solid, some of it is honest scaffolding, and a few docs were claiming victory a little early.

## Architecture Deep Dive

The shell is the front desk. `MainAuraView` decides whether you are checking in, waiting on data, or already inside the building. `MainTabView` is the hallway that points you toward Home, Music, Receipts, Tokens, and the rest.

`AccountStore` is the guestbook. It remembers who was added, who is active, and which chain each account is looking at. `NFTService` is the courier running out to fetch the latest collection data, while `ContextService` is supposed to be the concierge that turns raw state into "what the app currently knows." That concierge exists now, but it is still half-reading from handwritten notes and half-waiting for the real back office to show up.

Receipts are the black box recorder. The good news is that the recorder foundation is real: schema, storage, sanitization, export, reset. The not-yet-great news is that some important events still happen without leaving a paper trail.

## The Codebase Map

If you need the shell truth, start here:

- `Auralis/Auralis/Aura/MainAuraView.swift`
- `Auralis/Auralis/Aura/MainTabView.swift`
- `Auralis/Auralis/Aura/GlobalChromeView.swift`

If you need identity and persistence:

- `Auralis/Auralis/Accounts/AccountStore.swift`
- `Auralis/Auralis/DataModels/EOAccount.swift`

If you need context and provider seams:

- `Auralis/Auralis/AppContext.swift`
- `Auralis/Auralis/ContextService.swift`
- `Auralis/Auralis/Networking/ReadOnlyProviderSupport.swift`
- `Auralis/Auralis/Networking/NFTService.swift`

If you need receipts:

- `Auralis/Auralis/Receipts/ReceiptContracts.swift`
- `Auralis/Auralis/Receipts/SwiftDataReceiptStore.swift`
- `Auralis/Auralis/Receipts/DefaultReceiptPayloadSanitizer.swift`

If you need the verdict from this session:

- `Auralis/P0-Remediation-Checklist.md`

## Tech Stack & Why

SwiftUI is doing the shell work because the app is state-heavy and view composition matters more here than pixel-perfect imperative layout gymnastics.

SwiftData is the local filing cabinet because Phase 0 needs persistence for accounts, NFTs, and receipts without dragging in a bigger database story than the app has earned yet.

Swift Testing is the quiet hero in this repo. At first glance it looked like the project had almost no tests because a rough grep missed the syntax. Then the actual test target showed up like a magician pulling scarves out of a sleeve. Lesson: inspect the target before you declare the room empty.

## The Journey

### War story: the docs that got ahead of the code

The implementation plan had several tickets marked as completed, but the live shell chrome currently does not expose a freshness pill or a search quick action. That is the kind of mismatch that creates expensive confusion later because future tickets start building on a victory that never actually happened.

### War story: the fake "no tests" scare

An early search pass came back empty for tests. That was wrong. The repo uses Swift Testing, not just older XCTest naming patterns, so the first search pattern basically walked into a jazz club asking if anyone had seen a marching band. Once the right files were read, the picture changed: account, receipt, provider, context, and routing coverage are all meaningfully present.

### Aha moment

`P0-501` and `P0-201` are in much better shape than some of the flashier shell tickets. The foundation work is sturdier than the presentation layer claims around it. That is useful. It means remediation is more about truth-telling and finishing seams than rebuilding the basement.

### Gotcha

There is a difference between:

- "a ticket shipped a baseline slice"
- "the ticket is complete against original acceptance criteria"

This repo currently mixes those two sentences too freely in the docs. That is exactly how planning drift sneaks in.

## Engineer's Wisdom

A senior engineer does not let a planning document become folklore. If the acceptance criteria say "chrome includes freshness and search," then the code should show freshness and search, or the doc should say "baseline only, completion deferred." Anything in between is how teams accidentally create phantom dependencies.

Another rule worth keeping: foundations should be boring and strict. `AccountStore` and the receipt store are good examples. They have contracts, tests, and narrow ownership. The more the shell and context layers imitate that discipline, the less cleanup `P0-701B` will need later.

## If I Were Starting Over...

I would label every in-progress ticket as one of three things from day one:

- `foundation complete`
- `baseline slice shipped`
- `acceptance complete`

That tiny language change would have prevented most of this remediation pass.

I would also make the shell chrome acceptance test-driven earlier. A global header is exactly the kind of thing that feels done until someone asks, "Where is the freshness pill?" and then the room gets very quiet.

## The Journey

### Follow-up course correction

One important clarification landed right after the first remediation pass: freshness is not supposed to become a dedicated global-chrome pill right now. The product decision is that freshness lives in the context sheet. That changed the remediation shape in a useful way.

Instead of treating `P0-101B` and `P0-302` as "missing a chrome freshness indicator," the better framing is:

- `P0-101B` still needs the search quick action and doc cleanup
- `P0-302` still needs a cleaner freshness contract and stronger tests
- `P0-502`, `P0-402`, and `P0-303` are the real places where app-wide rollout work can happen now

This is a good example of why remediation work should separate product decisions from implementation gaps. If you confuse those two, you end up fixing the wrong thing very efficiently.

### Receipt slice closed

`P0-502` is now in better shape. The app can log launch, context builds, explorer opens, and the active copy action on top of the account, chain, and NFT refresh receipts that already existed. This matters because it turns the shell from "we think this happened" into "we can prove this happened."

The nice part is that this did not require a giant new subsystem. A small shared receipt logger was enough. That is the kind of change worth remembering: when the foundation is decent, finishing a feature often means adding one disciplined seam instead of three new managers with dramatic names.

### Context seam tightened

`P0-402` got a more honest shell-facing finish. The important change was not flashy UI. It was reducing duplicate truth. The mounted chrome and the context inspector now read the same `ContextSnapshot` instead of each quietly peeking at parallel pieces of shell state.

That matters because duplicate reads are how apps start disagreeing with themselves. One part says "Collector," another says a shortened address, another says stale, another says fresh, and suddenly everyone is debugging a ghost. A shared context seam is basically making the shell use one weather report instead of each room sticking its head out a different window.

### Degraded mode stopped being a newsfeed-only superstition

`P0-303` finally grew up from a one-screen trick into a shell behavior for the current NFT-backed surfaces. Before this pass, the newsfeed knew how to say "the provider failed, but your cached collection is still here." The music library and NFT token library were less articulate. They could show cached data, but they were not consistently honest about the failure that just happened.

The fix was intentionally boring: reuse the same shell status components and the same `NFTProviderFailurePresentation` contract instead of making each screen invent its own emergency sign. That is senior-engineer boring, which is good boring. When a failure story matters across multiple surfaces, one shared sentence is better than three improvised speeches.

There is still one important distinction to keep in mind. This closes the current NFT provider rollout. It does not magically mean every future provider-backed surface is done forever. If a new provider shows up later, it should inherit the same degraded-mode discipline instead of pretending the app has never learned this lesson before.

### Chrome contract made honest

`P0-101B` had one very specific missing tooth: the docs kept talking about chrome-level search, but the mounted chrome itself had no search action. The search tab existed. The route existed. The chrome just stood there and acted like someone else would handle it.

That kind of gap is sneaky because everything looks "basically done" until you evaluate the actual user path. The fix was small and exactly the sort of small thing that matters: add a real chrome search button, route it through `AppRouter`, and update the docs so they stop promising a separate freshness pill when the product decision is clearly "freshness details live in the context sheet."

This is the broader lesson: ticket cleanup is not just code cleanup. Sometimes the most important bug is that the code and the story disagree.
