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

## Engineer's Wisdom

If a type’s only public initializer becomes a classifier, tests should follow it. Otherwise the tests stop being customer-facing contracts and become secret friends with implementation details. Good tests do not ask for privileged backstage access unless that access is the thing being tested.

## If I Were Starting Over...

I would make the intended fixture story more obvious up front, either with dedicated test helpers or with a tiny set of factory methods next to the tests. When a type intentionally hides its memberwise init, that usually means the design wants every caller, including tests, to speak in domain events rather than raw stored properties.
