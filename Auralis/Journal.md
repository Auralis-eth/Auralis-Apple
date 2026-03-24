# Journal

## The Big Picture

Auralis is what happens when a wallet browser, an NFT gallery, a gas tracker, and a music player all end up in the same app shell and somehow make it work. The user picks an account, the app restores context, fetches inventory, persists it locally, and then lets that shared data power multiple surfaces instead of duplicating logic everywhere.

## Architecture Deep Dive

Think of the app as a small venue with a very busy lobby.

- `MainAuraView` is the lobby manager. It decides who is inside, which chain they are on, whether the app is still waiting on inventory, and when a deep link is safe to route.
- `NFTService` is the operations crew. It fetches inventory, parses metadata, persists changes, and clears stale records when the account or chain changes.
- The receipts layer is the black box recorder. It should never be dramatic. It just needs to be ordered, append-only, and trustworthy.
- `AudioEngine` is the stage crew. It loads tracks, swaps them, tears down stale temp files, and keeps the music UI informed without making the views know anything about `AVAudioEngine`.

## The Codebase Map

- `Auralis/Aura/` contains the shell, routing, and user-facing SwiftUI screens.
- `Auralis/DataModels/` holds the persistence layer and shared JSON/domain types.
- `Auralis/Networking/` is where provider integration and refresh orchestration live.
- `Auralis/Receipts/` keeps the event trail honest.
- `Auralis/MusicApp/AI/` is the active audio path.
- `Auralis/Helpers/` is the utility drawer, which is useful right up until it hides a sharp edge.

## Tech Stack & Why

- SwiftUI because the app is naturally state-first and benefits from a single declarative shell.
- SwiftData because NFTs, playlists, and receipts all need durable local state.
- Swift Concurrency because account changes, metadata refreshes, avatar generation, and audio loading all need real cancellation semantics.

## The Journey

### Bug War Stories

- Receipt sequencing was skipping values after warmup because the cache advanced one step too far. Quiet bug, dangerous consequences.
- Account refreshes were too polite to stale work. When the user switched accounts, old refresh tasks could keep running long enough to write data for the wrong scope.
- Tag colors were being normalized by the form one way and validated by the model another way. The classic “two bouncers, different guest list” problem.
- Audio downloads reused bare filenames in temp storage. Two remote tracks named `audio.mp3` is not a hypothetical on the internet; it is Tuesday.
- Trait parsing only accepted strings, which meant perfectly valid numeric metadata got dropped on the floor.

### Aha Moments

- Cancellation is not optional in this app. If stale tasks are allowed to finish, the UI can become technically successful and still wrong.
- Provider support needs to be explicit. Building a URL is not the same as having a real backend behind it.

## Engineer's Wisdom

- When state can change out from under a task, give the task an identity or cancel it.
- Normalize user input at the domain boundary, not just in the view.
- Temporary files deserve unique names. “Probably unique enough” is how ghost bugs get born.

## If I Were Starting Over...

I would make scope ownership even more explicit around account and chain changes. That is the part of the app where stale data keeps trying to re-enter wearing a valid-looking badge.
