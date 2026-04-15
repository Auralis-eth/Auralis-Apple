# Journal

## The Big Picture

Auralis is a wallet-aware NFT browser with a music engine hiding under the hood. The app lets you step into a public wallet, fetch what it owns, cache the collection locally, and then wander through art, tokens, and audio without needing to hold private keys like a dragon guarding a vault.

## Architecture Deep Dive

Think of the app like a museum with a front desk, a storage room, and a listening room.

`MainAuraView` is the front desk. It decides who is currently checked in, what chain they are visiting, and which room they should be sent to next.

`NFTService` is the storage crew. It fetches crates of NFT metadata from providers, cleans them up, deduplicates them, and shelves them in SwiftData so the UI is not living fetch-to-fetch like it forgot its lunch.

The music stack is the listening room. `MusicLibraryIndex` turns NFTs into playable catalog entries, and `AudioEngine` is the actual stereo system. That means media URLs are not decorative metadata. They are inputs that can make the app perform work, allocate memory, hit the network, and touch the file system.

## The Codebase Map

`Auralis/Aura/` is the shell and product UI.

`Auralis/DataModels/` holds the main persisted types like `NFT`, `EOAccount`, and token holdings.

`Auralis/Networking/` is where provider calls and refresh orchestration live.

`Auralis/Helpers/` is where parsing and URL normalization helpers sit. This folder now matters a lot for trust boundaries because media URL policy belongs close to ingestion, not scattered through random views.

`Auralis/MusicApp/AI/` is the active music feature path. If you are debugging playback, start there, not in `OLD/`.

## Tech Stack & Why

SwiftUI drives the app because the shell is state-heavy and route-heavy, which is exactly where declarative updates pay rent.

SwiftData stores fetched NFTs locally because the app wants a persistent collection view instead of making the user stare at loading spinners every time they breathe.

AVFoundation runs playback because once NFT metadata graduates into “play this audio,” you need the grown-up Apple media APIs, not a toy abstraction.

## The Journey

War story: untrusted NFT media URLs are a classic “this looks harmless until it isn’t” bug class. NFT metadata can point anywhere. That means `file:` URLs, malformed schemes, local bundle paths, giant remote files, weird gateways, and whatever else the internet had for breakfast.

What we changed:

- Added a single remote-media policy in `Auralis/Helpers/URL.swift`.
- Sanitized media URLs at ingestion time in `Auralis/Helpers/NFTMetadataUpdater.swift`.
- Made `NFT.musicURL` return only validated remote URLs.
- Removed fallback paths that would silently reuse raw `audioUrl` strings in the music index and detail presentation.
- Added loader-side guardrails so old persisted junk does not get a free pass.

Lesson learned: if metadata is untrusted, “we’ll validate it later” is engineering for future regret. The app should decide at the boundary whether something is a valid remote media URL and store only that answer.

Another war story: receipt tests can drift when the sanitizer gets smarter. This round was not a product regression so much as a trust-contract mismatch between old expectations and current payload policy. `errorKind` labels now sanitize to `"<redacted-label>"`, and some account-address receipt paths now collapse to `"<redacted-opaque-token>"` instead of older hashed-string expectations.

What we changed:

- Updated the receipt-focused tests to match the current sanitizer contract instead of the older redaction assumptions.
- Fixed a `SecretsTests` compile blocker caused by using `#expect(throws:)` with a non-`Equatable` error path.
- Revalidated that the app target still builds cleanly after the test-only fixes.

Lesson learned: when tests assert on sanitized payloads, they are asserting on policy, not just data. If the privacy contract changes, update the tests to describe the new contract explicitly or they turn into archaeological artifacts.

## Engineer's Wisdom

Good engineers separate “data we received” from “data we are willing to act on.” Those are not the same thing.

If a value can trigger network I/O, disk I/O, or file reads, it is not just display data anymore. It is effectively a command input, and it deserves a policy.

Defense in depth is not paranoia here. Sanitizing media URLs during parsing is good. Re-checking them in the image/audio loaders is also good. Old persisted rows, future migrations, and partially trusted imports are how weird bugs sneak past “but we already validate that.”

## If I Were Starting Over...

I would make URL trust policy a first-class type much earlier. Something like `TrustedRemoteMediaURL` would be cleaner than letting raw strings drift through the model and hoping every consumer remembers to behave.

I would also add size and MIME enforcement closer to the network layer for images and audio so malicious NFTs cannot turn the app into a bandwidth vacuum cleaner.

War story: Phase 0 planning docs multiplied like rabbits with clipboards. That was useful while the work was moving, but bad project memory once the dust settled. The repo now keeps one compact `Phase-0-LLM-Handoff.md` file for the durable decisions and leaves the temporary ticket choreography in the trash where it belongs.
