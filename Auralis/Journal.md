# The Big Picture

Auralis is a wallet-aware SwiftUI app that treats NFTs like first-class media, identity, and navigation inputs. The app shell restores an account, scopes data by chain, fetches NFT inventory, and then routes that state across Home, News, Gas, Receipts, and Music without pretending those are separate products.

# Architecture Deep Dive

The shell works like an airport control tower. `MainAuraView` and friends decide which runway is active, which account is in scope, and which long-lived services stay alive. Networking brings cargo in, SwiftData stores it in the hangar, and the feature tabs consume the same shared inventory rather than each building their own importer.

# The Codebase Map

- `Auralis/Aura/`: shell and product surfaces
- `Auralis/DataModels/`: persisted models and domain types
- `Auralis/Networking/`: provider orchestration, fetchers, throttling, config
- `Auralis/Gas/`: gas fee presentation and polling
- `Auralis/MusicApp/AI/`: active music engine and UI

# Tech Stack & Why

SwiftUI drives the UI because the app is heavily state-scoped by account and chain. SwiftData holds local inventory because the product needs persistence, filtering, and relationship reuse without bolting on a separate database layer. Async/await is the right fit for fetch orchestration and long-lived services because it keeps cancellation and scope changes legible.

# The Journey

- A force unwrap in `OpenSeaLink` looked harmless because the hosts are hardcoded, but that is exactly how crash landmines age badly. The fix was to construct the explorer destination through `URLComponents` so malformed future edits fail closed instead of taking down the UI.
- Search had a classic “dictionary ate my data” bug. NFT names and collection names were deduped by normalized text, which meant two identically named NFTs collapsed into one result. The fix preserves duplicate NFT name matches and only dedupes collections by a scoped identity.
- `GasPriceEstimateViewModel` used a repeating `Timer` that retained `self`. It would usually unwind eventually, but “usually” is not a lifecycle policy. The timer now captures weakly and hands work back into a main-actor helper.
- `AlchemyNFTService` logged the full provider base URL. In a codebase where API keys can live inside URLs, that is an accidental credential spill waiting for a log export. Logging now stops at the host.

# Engineer's Wisdom

Good engineering is often subtractive. Removing a force unwrap, removing accidental deduplication, and removing a credential-bearing log line each make the system safer without making it fancier. The trick is to treat “probably fine” as suspicious when the blast radius is a crash, silent data loss, or secret leakage.

# If I Were Starting Over...

I would split `NFT.swift` much earlier. It currently behaves like an overpacked suitcase: model, tag UI, color helpers, and sample data all jammed together. It still zips, but every change risks knocking loose something unrelated.
