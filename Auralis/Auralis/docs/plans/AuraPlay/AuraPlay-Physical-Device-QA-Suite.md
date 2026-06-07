# AuraPlay Physical Device QA Suite

This is the real-device QA suite for the AuraPlay rebuild path. The simulator is useful for speed. It is not where audio session behavior, background playback, interruptions, route changes, and “why does this feel wrong in the hand?” issues tell the truth.

The current shipping scope for this suite is the Phase 3 baseline: wallet-scoped sync into the AuraPlay store, persisted-library preference, module-owned storage resolution, shell-scope changes, and the still-shared playback engine. Search, playlists, and durable playback history are later-phase items and should be marked `Not In Scope Yet` when absent rather than filed as false regressions.

## Test Environment Template

Record this before starting:

- device model
- iOS version
- app build/version
- build configuration
- network condition: normal Wi-Fi, weak Wi-Fi, cellular, offline
- account used for testing
- chain scope(s) tested
- whether the Music tab is running through the legacy root or AuraPlay root
- whether the active wallet has already been mirrored into the AuraPlay persisted store
- whether the tested media/artwork includes IPFS, Arweave, HTTP/HTTPS, or `data:` URI inputs
- whether any gateway fallback behavior was observed or deliberately exercised

## Exit Rule

AuraPlay device QA passes only when:

- all blocking tests below pass
- no crash, stuck playback state, broken route change, or unrecoverable navigation wedge remains
- supported Phase 3 storage inputs do not surface as raw or broken URLs in migrated AuraPlay paths
- any known issues are documented with severity, repro steps, and owner

## AP-Device-001: Cold launch into the Music tab

Goal:

- verify the shell can launch cleanly and route into the music surface

Steps:

1. Install or launch a fresh build.
2. Enter a valid account with playable music NFTs.
3. Open the Music tab immediately.
4. Terminate and relaunch.
5. Re-open Music.

Pass criteria:

- no blank root, crash, or frozen launch path
- the Music tab lands in a sane state on first and second launch

## AP-Device-002: AuraPlay root seam sanity

Goal:

- confirm the Music tab swap seam does not corrupt shell behavior

Steps:

1. Open Music from Home.
2. Switch to another root tab.
3. Return to Music.
4. Open a routed detail if available.
5. Switch accounts and chains while Music has been visited.

Pass criteria:

- shell routing remains coherent
- account or chain changes do not leave stale music scope onscreen

## AP-Device-003: Library browse behavior

Goal:

- validate the current persisted-library migration seam and the first migrated browse surface once it exists

Steps:

1. Open Music on an account with multiple playable items.
2. Confirm the first open can tolerate an unsynced wallet scope.
3. Leave and re-enter Music after the wallet has been mirrored.
4. Scroll the library.
5. Inspect artwork loading, availability labels, and empty/degraded states.
6. Pull to refresh or trigger the equivalent rebuild path if exposed.

Pass criteria:

- the first visit can populate the AuraPlay persisted store without user-visible corruption
- a later visit prefers the persisted AuraPlay media graph instead of behaving like a perpetual cold start
- playable and non-playable items are distinguishable
- no artwork flicker, stale scope leakage, or obviously wrong availability state appears
- migrated artwork URL preparation accepts supported IPFS, Arweave, HTTP/HTTPS, and `data:` inputs without falling back to visibly broken URLs

## AP-Device-004: Playback controls

Goal:

- verify the highest-risk user-facing music behaviors

Steps:

1. Start playback.
2. Pause and resume.
3. Use next and previous.
4. Seek if the current surface exposes it.
5. Confirm mini-player and any full-player UI stay in sync.

Pass criteria:

- playback state stays coherent
- controls do not wedge or point at the wrong track
- UI state matches actual audio behavior

## AP-Device-004A: Storage-resolution product paths

Goal:

- verify the Phase 3 resolver seam behaves like product infrastructure on device, not a visible technical layer

Steps:

1. Open Music on fixture or real-account media that includes IPFS artwork or audio.
2. Repeat with Arweave media if available.
3. Repeat with normal HTTP/HTTPS media.
4. Repeat with a small `data:` artwork/media item if the fixture path exposes one.
5. Trigger the visible loading path for each item.

Pass criteria:

- supported IPFS, Arweave, HTTP/HTTPS, and `data:` inputs resolve into ordinary artwork/media behavior on migrated AuraPlay paths
- cleartext `http://` inputs do not remain cleartext in migrated URL-preparation paths
- unsupported or malformed storage strings degrade through the normal AuraPlay failure state rather than showing raw technical strings
- gateway fallback, if exercised, does not block navigation or duplicate loading UI

## AP-Device-005: Background playback

Goal:

- verify the app-level audio contract on real hardware

Steps:

1. Start playback.
2. Lock the device.
3. Wait while playback continues.
4. Unlock and return.
5. Background and foreground the app multiple times.

Pass criteria:

- background playback behaves as intended
- foreground return does not desynchronize controls or track metadata

## AP-Device-006: Audio interruptions and route changes

Goal:

- catch device-only audio-session failures

Steps:

1. Start playback.
2. Connect and disconnect headphones or Bluetooth audio if available.
3. Trigger another audio app or interruption event if possible.
4. Return to Auralis and attempt resume.

Pass criteria:

- route changes do not strand the engine or UI
- interruption recovery leaves the app in a sane paused or resumed state

## AP-Device-007: Rapid track changes and stale-load replacement

Goal:

- validate the place lifecycle bugs like to hide

Steps:

1. Start a track.
2. Trigger next or another track change before the prior load fully settles.
3. Repeat quickly several times.
4. Return to the prior track if possible.

Pass criteria:

- stale loads do not “win” and show the wrong track
- controls remain responsive
- the app does not wedge in loading forever

## AP-Device-008: Account and chain scope changes during music use

Goal:

- verify shell-owned scope changes do not poison the music module

Steps:

1. Open Music on account A.
2. Switch to account B.
3. Switch chain scope.
4. Return to account A.
5. Re-open Music details if available.

Pass criteria:

- visible music data always matches the active account and chain
- switching back to a previously mirrored scope does not show another wallet's persisted media
- detail stacks do not show stale content from the prior scope

## AP-Device-009: Offline and degraded mode

Goal:

- confirm the rebuild handles provider and network turbulence honestly

Steps:

1. Open Music on a healthy network.
2. Disable network before or during a refresh/rebuild action.
3. Return network and retry.
4. Repeat on a sparse or no-audio account if available.

Pass criteria:

- failure and retry behavior are understandable
- a previously mirrored wallet can still surface sane persisted-library state when live refresh is impaired
- the user can navigate away instead of getting trapped in a dead surface
- degraded states do not impersonate healthy live state

## AP-Device-010: Persisted-store continuity across relaunch

Goal:

- validate that the current Phase 3 persistence and storage-resolution baseline survives normal app lifecycle churn

Steps:

1. Open Music on a wallet with playable music NFTs and allow sync to complete.
2. Leave Music, terminate the app, and relaunch.
3. Return to Music on the same account and chain.
4. Switch away to another account or chain, then return.

Pass criteria:

- the relaunch path does not lose the mirrored wallet/media graph unexpectedly
- the same wallet scope can re-open into a sane persisted-library state
- account and chain changes still gate what persisted media is shown

## AP-Device-011: Playlist and artwork flows

Goal:

- validate later-phase music-adjacent camera/photo-library paths when they are active

Steps:

1. Create or edit a playlist if the flow is active.
2. Choose photo-library artwork.
3. Capture artwork with the camera if that path is active.
4. Relaunch and confirm persistence.

Pass criteria:

- permission prompts match the feature being used
- artwork selection persists and does not corrupt the flow

If inactive:

- mark `Not In Scope Yet` instead of filing a product bug against the current Phase 3 baseline

## Severity Rubric

- `Blocker`: crash, stuck playback, broken scope, broken background audio, unrecoverable navigation, privacy-reset failure
- `Major`: wrong track shown, wrong scope shown, repeated playback-control failure, severe layout break, stale metadata that misleads the user
- `Minor`: polish issue, awkward animation, small visual defect, intermittent stale label without data corruption

## Final Test Report Template

- build tested:
- devices tested:
- accounts/chains tested:
- AuraPlay root or legacy root:
- blocker bugs:
- major bugs:
- minor bugs:
- deferred issues:
- go / no-go:
