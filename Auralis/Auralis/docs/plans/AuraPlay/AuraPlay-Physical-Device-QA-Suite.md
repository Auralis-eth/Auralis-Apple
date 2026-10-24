# AuraPlay Physical Device QA Suite

**Last reconciled with code:** 2026-10-22
**Execution status:** Not run for the current release candidate unless a signed result is recorded in the final report below.

This is the real-device QA suite for the shipping AuraPlay path. The simulator is useful for speed. It is not where audio session behavior, background playback, interruptions, route changes, and “why does this feel wrong in the hand?” issues tell the truth.

The current shipping scope is the assembled AuraPlay release path: provider-authoritative wallet/chain discovery into the AuraPlay store, module-owned storage resolution, shell-scope changes, search and Spotlight, receipt-backed playlists, safe auto-organization previews, user metadata overrides, durable playback history, and package-owned audio/video engines. This is the single manual hardware gate for AuraPlay. Do not claim support for any listed wallet/provider until its route has passed on hardware.

## Test Environment Template

Record this before starting:

- device model
- iOS version
- app build/version
- build configuration
- network condition: normal Wi-Fi, weak Wi-Fi, cellular, offline
- account used for testing
- chain scope(s) tested
- whether the Music tab is running through the current `MusicFeatureRootView` path and whether any legacy playlist helper path is being exercised
- whether provider discovery has populated the active wallet/chain AuraPlay graph
- whether the tested media/artwork includes IPFS, Arweave, HTTP/HTTPS, or `data:` URI inputs
- whether any gateway fallback behavior was observed or deliberately exercised
- third-party wallet/provider under test, wallet app or SDK environment version, account/network, and whether support is claimed or blocked

## Exit Rule

AuraPlay device QA passes only when:

- all blocking tests below pass
- no crash, stuck playback state, broken route change, or unrecoverable navigation wedge remains
- supported storage inputs do not surface as raw or broken URLs in AuraPlay paths
- accessibility, privacy reset, video-system integration, search/indexing, metadata override, and safe auto-organization checks below have signed results
- any known issues are documented with severity, repro steps, and owner

## Required Third-Party Wallet Support Matrix

Production support cannot be claimed for a wallet/provider below until the named route passes on a physical device. Record each pass/fail in the final test report.

| Route family | Wallet/provider | Required proof |
| --- | --- | --- |
| EVM WalletConnect/Reown | Rabby | Connect, reject/cancel, `personal_sign` ownership verification, disconnect from both sides, restore/fail-closed on relaunch, and callback round-trip exactly once. |
| EVM WalletConnect/Reown | Rainbow | Connect, reject/cancel, `personal_sign` ownership verification, disconnect from both sides, restore/fail-closed on relaunch, and callback round-trip exactly once. |
| Direct/native EVM | Coinbase Wallet | Direct route connect, reject/cancel, ownership verification, disconnect, restore/fail-closed on relaunch, and callback round-trip exactly once. |
| EVM WalletConnect/Reown | MetaMask | Connect, reject/cancel, `personal_sign` ownership verification, disconnect from both sides, restore/fail-closed on relaunch, and callback round-trip exactly once. |
| Solana wallet route | Phantom | Connect, reject/cancel, Solana message-sign ownership proof, disconnect from both sides, restore/fail-closed on relaunch, and callback round-trip exactly once. |
| Solana wallet route | Backpack | Connect, reject/cancel, Solana message-sign ownership proof, disconnect from both sides, restore/fail-closed on relaunch, and callback round-trip exactly once. |
| Solana wallet route | Solflare | Connect, reject/cancel, Solana message-sign ownership proof, disconnect from both sides, restore/fail-closed on relaunch, and callback round-trip exactly once. |
| Embedded/auth route | Privy | Login/connect, reject/cancel where supported, ownership verification, logout/disconnect, restore/fail-closed on relaunch, and callback round-trip exactly once. |
| Embedded/auth route | Dynamic | Login/connect, reject/cancel where supported, ownership verification, logout/disconnect, restore/fail-closed on relaunch, and callback round-trip exactly once. |

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

## AP-Device-004B: Phase 6 audio-engine release gate

Goal:

- sign off the hardware-only behavior that cannot be proven by simulator or package tests

Steps:

1. Start a representative cached AuraPlay audio track and keep Now Playing open.
2. Background the app and lock the screen.
3. Confirm Lock Screen title, artist, artwork, elapsed time, play/pause, skip, and scrub controls.
4. Connect AirPods or another Bluetooth route mid-playback.
5. Disconnect that route mid-playback.
6. Trigger an interruption with a phone call or Siri.
7. Play an uncached supported track on a poor network and observe progressive buffering/recovery.
8. Play a known gapless pair or album with both tracks cached.
9. Try an unsupported `.ogg` or `.opus` item if test media is available.
10. Run one hour of background audio on a recent physical device.

Pass criteria:

- background audio continues when the app is backgrounded and locked
- Lock Screen and Control Center metadata are correct and elapsed time advances
- remote commands map to the active AuraPlay transport
- Bluetooth connect/configuration changes recover without silent playback death
- Bluetooth disconnect pauses instead of unexpectedly playing through the speaker
- interruption end resumes from the same position when the system indicates playback should resume
- poor-network playback shows buffering/recovery instead of a raw technical error
- cached gapless transitions have no audible gap on representative media
- unsupported formats show the product unsupported-format copy
- one-hour background playback stays within the current battery target or records a signed known issue

Sign-off:

- Owner:
- Date:
- Device / iOS:
- Build:
- Result: Not Run

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
- a previously discovered wallet can surface honest persisted state when live refresh is impaired without presenting it as a successful refresh
- the user can navigate away instead of getting trapped in a dead surface
- degraded states do not impersonate healthy live state

## AP-Device-010: Persisted-store continuity across relaunch

Goal:

- validate that the shipping persistence and storage-resolution baseline survives normal app lifecycle churn

Steps:

1. Open Music on a wallet with playable music NFTs and allow sync to complete.
2. Leave Music, terminate the app, and relaunch.
3. Return to Music on the same account and chain.
4. Switch away to another account or chain, then return.

Pass criteria:

- the relaunch path does not lose the provider-discovered wallet/media graph unexpectedly
- the same wallet scope can re-open into a sane persisted-library state
- account and chain changes still gate what persisted media is shown

## AP-Device-011: Shipping playlist flows

Goal:

- validate the receipt-backed AuraPlay playlist store and its no-op rules

Steps:

1. Create a playlist and add two playable items.
2. Rename it, reorder its entries, remove an entry, and relaunch.
3. Repeat a rename, membership, or reorder action that makes no effective change.
4. Delete the playlist.
5. Inspect the receipt timeline for each effective mutation and the no-op action.

Pass criteria:

- playlist membership and order persist across relaunch
- create, rename, membership, reorder, and delete mutations emit receipts
- no-op mutations emit no receipt
- the compatibility primary-store playlist model is neither displayed as an AuraPlay playlist nor silently synchronized into one

## AP-Device-012: Video system integration

Steps:

1. Play representative video in-line and full screen.
2. Enter and restore Picture in Picture.
3. Route playback through AirPlay when hardware is available.
4. Exercise subtitles, audio descriptions, and playback speed on media that exposes them.
5. Background, foreground, lock, interrupt, and rotate while video is active.

Pass criteria:

- player state and the visible track remain coherent across full-screen, PiP, route, and lifecycle transitions
- advertised accessibility tracks and playback speeds work and persist as designed
- unsupported WebM media produces the documented unsupported-format experience rather than a crash or hang

## AP-Device-013: Search, Spotlight, auto-organization, and metadata overrides

Steps:

1. Search by title, creator, collection, and a semantic-only phrase; rapidly replace the query once.
2. Open an indexed AuraPlay item from Spotlight and confirm it resolves to the correct scoped item.
3. Request an auto-organization proposal and review its explanation and receipt evidence.
4. Cancel the proposal and confirm no playlist changed; if an apply control is absent, confirm the UI does not imply that mutation occurred.
5. Override a title, creator, or artwork value and verify it in Library, search, Spotlight, semantic results, player surfaces, and after relaunch.
6. Refresh provider metadata and confirm the user override remains authoritative.

Pass criteria:

- stale search tasks never replace newer results and Spotlight opens the correct scoped item
- auto-organization is preview-only, receipt-backed, and cannot mutate playlists
- user metadata overrides remain consistent across every consumer and survive provider refresh

## AP-Device-014: Privacy reset and accessibility

Steps:

1. Populate history, recents, cache, search, playlists, playback positions, Spotlight entries, and metadata overrides.
2. Run the product privacy-reset flow, confirm it, terminate, and relaunch.
3. Verify deleted local state does not reappear before a new authorized discovery/index operation.
4. Repeat key Library, Search, Playlist, Now Playing, video, error, and confirmation flows with VoiceOver.
5. Repeat at an accessibility text size, Increase Contrast, Reduce Motion, and Reduce Transparency.

Pass criteria:

- reset clears every state category promised by its confirmation copy and does not cross into another account unexpectedly
- primary controls, states, errors, and destructive confirmations are named, reachable, ordered, and operable with VoiceOver
- layouts remain usable without clipped required controls; motion and transparency respond to system accessibility settings

## Severity Rubric

- `Blocker`: crash, stuck playback, broken scope, broken background audio, unrecoverable navigation, privacy-reset failure
- `Major`: wrong track shown, wrong scope shown, repeated playback-control failure, severe layout break, stale metadata that misleads the user
- `Minor`: polish issue, awkward animation, small visual defect, intermittent stale label without data corruption

## Final Test Report Template

- build tested:
- devices tested:
- accounts/chains tested:
- wallet/provider matrix results: Rabby, Rainbow, Coinbase Wallet, MetaMask, Phantom, Backpack, Solflare, Privy, Dynamic
- per-case results: AP-Device-001 through AP-Device-014 (Pass / Fail / Blocked / Not Run)
- MusicFeatureRootView path and any legacy playlist helper exercised:
- blocker bugs:
- major bugs:
- minor bugs:
- deferred issues:
- go / no-go:
