# NFTLibraryFeature Journal

## The Big Picture

NFTLibraryFeature is the part of Auralis that turns a wallet's NFT inventory into something you can actually browse. Think of it as the gallery wing of the app: it does not own the whole museum, but it decides how the collection is sorted, framed, opened, and explained when something goes wrong.

## Architecture Deep Dive

The package works like a small front-of-house team. `NFTLibraryRoute` and `NFTLibrarySort` decide where visitors are going and in what order the art appears. `NFTLibraryPresentation` translates raw NFT model data into clean display text, collection groupings, and stable navigation ids. The SwiftUI views handle the room layout, while `NFTImageLoader` is the careful art handler that fetches previews, rejects media it cannot safely show, and keeps oversized files from barging through the door.

## The Codebase Map

- `Sources/NFTLibraryFeature/Domain/` holds route and sorting values.
- `Sources/NFTLibraryFeature/Presentation/` holds SwiftUI screens, cards, image loading, sort controls, and status views.
- `Sources/NFTLibraryFeature/Services/` defines dependency surfaces that the app can plug into.
- `Sources/NFTLibraryFeature/Support/` holds presentation mapping logic that should stay testable outside the views.
- `Tests/NFTLibraryFeatureTests/` covers image loading, presentation mapping, route behavior, and sorting.

## Tech Stack & Why

SwiftUI carries the UI because this package is primarily feature presentation and benefits from state-driven rendering. Swift Testing backs the unit tests because the package logic is small, focused, and easy to express with direct expectations. `AuralisPrimaryModels` supplies the shared NFT and chain models so this feature boundary stays aligned with the rest of the app instead of growing its own lookalike types.

## The Journey

### 2026-05-15: Extensionless Videos and Contract Identity

Two test failures exposed useful edge cases. First, extensionless NFT media can still be video; relying only on `.mp4` in the URL is like checking someone's passport by their hat. `NFTImageLoader` now checks the response MIME type and rejects `video/*` and `application/mp4` before trying to decode bytes as an image.

Second, collection membership can be described by `NFT.contract.address` or by `NFT.collection.contractAddress`. The collection detail presentation now checks both normalized addresses. The test also reminded us that `NFT` rewrites ids into scoped persistence ids during initialization, so presentation tests should compare against the model's actual `id`, not the friendly fixture label.

## Engineer's Wisdom

Keep view code boring and let tested presentation helpers do the tricky translation work. Also, never trust file extensions for media type decisions when the server has already handed you a MIME type. The server's label is not perfect, but it is a much better first gate than hoping every NFT URL ends neatly.

## If I Were Starting Over...

I would make the distinction between fixture labels, provider ids, and scoped persistence ids explicit in the test factory. A tiny `fixtureLabel` helper would make tests read nicely without implying that `NFT.id` survives initialization unchanged.
