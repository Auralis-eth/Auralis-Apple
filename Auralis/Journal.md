# Journal

## The Big Picture

Auralis is what happens when a wallet explorer, an NFT gallery, a gas dashboard, and a music player all decide to live in the same apartment and mostly get along. The app restores a wallet context, fetches NFT and token data, persists the useful pieces locally, and then turns that data into a few distinct product surfaces instead of one giant scrolling junk drawer.

## Architecture Deep Dive

The app shell is the stage manager. `MainAuraView` and its surrounding shell code decide who gets to walk on stage: auth, loading, or the main experience. `NFTService` is the logistics crew behind the curtain. It talks to the fetcher, classifies provider failures, keeps SwiftData in sync, and makes sure the UI gets a clean story instead of raw network chaos.

Think of `NFTFetcher` as the delivery driver and `NFTService` as the restaurant expediter. The driver brings in boxes from the provider. The expediter checks whether the order makes sense, decides whether a delay is temporary or serious, and tells the dining room what to say to the customer.

## The Codebase Map

`Auralis/Auralis/Aura/` is the visible product shell and feature UI.

`Auralis/Auralis/Networking/` is where provider communication, throttling, and refresh orchestration live.

`Auralis/Auralis/DataModels/` holds the durable shapes the app cares about.

`Auralis/Auralis/MusicApp/AI/` is the active music path. `OLD/` is the attic. Useful for archaeology, dangerous for assumptions.

`AuralisTests/` contains contract-style coverage for presentation logic, routing, persistence helpers, and service behavior.

## Tech Stack & Why

SwiftUI is doing the UI work because the app is heavily state-driven and that matches the problem well. SwiftData handles local persistence so the app can keep useful state on-device instead of treating every screen as a fresh network gamble. Swift Concurrency is the right fit for refresh pipelines, background loading, and “this can fail, but don’t freeze the UI” work.

## The Journey

One recent bug had a very familiar smell: tests were still constructing `NFTProviderFailure` with the old memberwise initializer even though production had moved to a failable `init(error:)` classifier. That made the tests compile against a version of the API that no longer existed, which is the software equivalent of trying to unlock your front door with a hotel keycard from last month.

The fix was to route test fixtures through the same typed error mapping that production uses. Offline cases now come from `URLError(.notConnectedToInternet)`, rate-limit cases come from `NFTFetcher.FetcherError.rateLimited`, and invalid-response coverage comes from `DecodingError`. That keeps the tests honest: they now verify the public behavior instead of relying on construction shortcuts that production code cannot use.

Another bug was less about logic and more about test physics. `ProviderAbstractionTests` used a single global `URLProtocol` handler while Swift Testing was free to run async tests in parallel. That is like giving four bartenders one shared cocktail shaker and then acting surprised when the martini tastes faintly like someone else's margarita. The symptom was wonderfully misleading: `tokenHoldingsProviderUsesBalanceEndpointAsAmountAuthority()` would occasionally crash with an index-out-of-range because another test had already swapped the mock network handler.

The fix was to serialize that suite so the shared mock state stops racing itself. In the same cleanup pass, the chrome and address-entry contract tests were brought back in line with the user-facing wording they actually assert, and the ERC-20 presentation tests stopped using ancient fixed timestamps for cases that are supposed to represent fresh metadata. That last one matters because time-based tests love turning into tiny gremlins if you accidentally ask 1970 to behave like “just updated.”

Then came the sneaky cursor bug. A pagination fixture used `pageKey.flatMap(Int.init)` and on this setup that behaved like a hex-flavored parser. So page keys walked `10 -> 17 -> 24 -> 37`, which made a perfectly healthy fetcher look like it was giving up after 14 pages. The lesson: if a cursor is decimal, say so out loud with `Int(value, radix: 10)`. Leaving number parsing to “whatever overload the compiler picked today” is how you end up debugging ghosts.

Another design fork looked attractive on paper and expensive everywhere else: turning guest passes into a full deterministic demo-data product mode. That path would have added bundled datasets, separate provenance rules, and second-source behavior across every major tab. After walking into the implementation weeds, the better call was to stop. Guest passes stayed as curated public-wallet shortcuts, and the app did not grow a parallel fake-data universe just to make screenshots feel tidy. Sometimes the senior-engineering move is not heroic completion; it is backing out of the side quest before it becomes permanent rent.

That decision clarified the offline story too. SwiftData already gives the app a real local persistence layer, which means the default offline behavior is straightforward: show what is already cached locally, surface provider failure honestly, and do not invent a special “offline mode” product unless the product truly needs one. A clean degraded mode beats a theatrical fake mode.

## Engineer's Wisdom

If a type’s only public initializer becomes a classifier, tests should follow it. Otherwise the tests stop being customer-facing contracts and become secret friends with implementation details. Good tests do not ask for privileged backstage access unless that access is the thing being tested.

Shared mutable state inside tests is a trap with nicer branding. If a suite relies on a global mock, either isolate it per test or serialize the suite on purpose. Parallel execution is not the villain here; vague ownership is.

Cursor parsing is another place where explicit beats clever. If the protocol says decimal, parse decimal. Tiny ambiguities in test fixtures can impersonate production regressions for hours.

Guest passes still need rigor, but they do not need to become a whole second application. A lightweight public-wallet shortcut is cheap to reason about. A fake cross-tab demo universe is not.

## If I Were Starting Over...

I would make the intended fixture story more obvious up front, either with dedicated test helpers or with a tiny set of factory methods next to the tests. When a type intentionally hides its memberwise init, that usually means the design wants every caller, including tests, to speak in domain events rather than raw stored properties.
