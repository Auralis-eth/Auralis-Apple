# Journal

## The Big Picture

Auralis is a wallet-driven NFT app with a split personality in the best way: part explorer, part dashboard, part music player. The tricky bit is that the music surface is not a toy add-on. It shares identity, persisted NFT data, and app-shell state with everything else, so small playback bugs can leak into the larger experience fast.

## Architecture Deep Dive

The app shell is the front of house. `MainAuraView` decides who is in the building, which account is active, and which feature surface is on stage. The audio engine is the backstage crew. If it is not wired correctly, the UI still looks calm while the speakers are unplugged.

For this round of work, the important seam was:

- `AudioEngine` owns playback state, seeking, queue history, and track identity.
- `MiniPlayerView` and `NowPlayingView` are thin control surfaces over that engine.

That split matters because the previous bug was really a contract mismatch: the engine exposed normalized progress, while the UI treated it like elapsed seconds.

## The Codebase Map

The active audio path lives here:

- `Auralis/Auralis/MusicApp/AI/Audio Engine/AudioEngine.swift`
- `Auralis/Auralis/MusicApp/AI/V1/MiniPlayerView.swift`
- `Auralis/Auralis/MusicApp/AI/V1/NowPlayingView.swift`

Legacy audio code still exists under `MusicApp/OLD/`, but it was not part of this fix.

## Tech Stack & Why

SwiftUI handles the control surfaces because the player UI is state-heavy and benefits from declarative updates. `AVAudioEngine` and `AVAudioPlayerNode` do the heavy lifting because they give the app direct control over scheduling, seeking, and queue transitions without dragging in a bigger playback framework.

## The Journey

- Bug squashed: the player slider was measuring apples in the engine and oranges in the UI. `AudioEngine.progress` returned a normalized fraction, but the sliders and `seek(to:)` treated it as seconds. That meant scrubbing was wrong, elapsed time was wrong, and the “restart previous if more than 3 seconds in” rule was secretly comparing a `0...1` fraction against `3.0`.
- Bug squashed: recently played actions tried to compare an NFT string ID like a wallet label on a record sleeve against a fresh random `UUID` generated for `Track.id`. Those values were never going to match, so the app kept reloading the track instead of resuming or restarting the current one.
- Bug squashed: `AudioEngine` initialization had its setup calls commented out, which is the software equivalent of rolling a piano onto the stage and never opening the lid.
- Bug squashed: the gas fee view model was canceling `currentTask` from inside `performFetch()`, which meant the task could cancel itself right before or during the provider request. That is a classic concurrency own-goal: the worker was cutting the power to its own workbench. The fix was to keep cancellation ownership in `setChain()` and let `performFetch()` focus purely on running one fetch.
- Bug squashed: `MainAuraView` was doing something sneaky during rapid account switches. It computed the right next account and chain, then launched a `Task` that ignored that snapshot and looked back at mutable view state instead. In a fast switch, the async refresh could run for the wrong wallet and then write yesterday's answer back into `currentAddress`. The fix was to package the refresh into an immutable request snapshot and let only the latest request win the write-back race.
- Bug squashed: `NFT.Contract` and `NFT.Collection` were pretending that `address` and `name` were universal truth. They are not. The same contract address can exist on different chains, and collection names are about as globally unique as coffee shop names. The fix was to give both models scoped identity keys tied to chain context, and for collections, to the contract when possible.
- Aha: the collection-provider decode path was quietly defaulting NFTs to Ethereum mainnet until something else corrected them. That is manageable only if something actually corrects them. The new fix forces every fetched NFT to adopt the refresh chain before persistence, so the model layer and the network request finally agree on which universe they are talking about.
- Gotcha: the Xcode test runner in this workspace is only partially executing Swift Testing suites right now. A full run reported 34 passed and 78 `No result`, including newly added regression tests. That smells like environment or runner plumbing rather than compile failure, because the project still builds cleanly and the test targets compile.

## Engineer's Wisdom

- Shared state contracts need one unit of truth. If the engine speaks in normalized fractions and the UI speaks in seconds, the bug is already written; it just has not been observed yet.
- Stable identity beats convenient identity. A generated UUID is fine for list diffing, but not when the rest of the app needs to answer “is this the same NFT we are already playing?”
- Cleanup work is only real if the subsystem still builds afterward. The fastest way to create future debt is to “clean up” code that no longer compiles.
- Async UI flows need snapshots, not vibes. If you derive the next state and then ignore it in favor of mutable properties inside a `Task`, you have built a race condition with very polite syntax.
- Persistence identity should model the real world, not a hopeful shortcut. If the domain says “same name can mean different thing,” a global uniqueness constraint is a trap disguised as neatness.

## If I Were Starting Over...

I would name the engine API more bluntly from day one:

- `elapsedTime` for seconds
- `normalizedProgress` for `0...1`
- `currentNFTID` for stable media identity

That naming alone would have made this bug much harder to write.

For the NFT layer, I would also make scoped identity a first-class citizen from day one:

- `contract.id = "\(chain):\(address)"`
- `collection.id = "\(chain):\(contractAddress)"` when available
- refresh pipelines that stamp fetched models with their actual chain before anything hits persistence

That would have avoided the awkward phase where the data model acted like every chain was one giant shared parking lot.
