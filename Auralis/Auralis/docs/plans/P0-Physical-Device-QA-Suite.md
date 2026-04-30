# P0 Physical Device QA Suite

This is the manual QA suite for Phase 0 on a real iPhone. The simulator is useful for speed. It is not where audio routing, camera permission prompts, app lifecycle timing, thermal behavior, and "feels broken in the hand" issues tell the truth.

## Test Environment Template

Record this before starting:

- device model
- iOS version
- app build/version
- build configuration
- network condition: normal Wi-Fi, weak Wi-Fi, cellular, offline
- account used for testing
- chain scope(s) tested
- whether this is a clean install, upgrade install, or relaunch pass

## Exit Rule

Phase 0 real-device QA passes only when:

- all blocking tests below pass
- no crash, persistent loading wedge, or unrecoverable navigation state remains
- any known issues are documented with severity, repro steps, and owner

## P0-Device-001: Clean install and first launch

Goal:

- verify the app reaches the expected gateway state on a real device

Steps:

1. Delete the app from the device.
2. Install a fresh build.
3. Launch once.
4. Lock and unlock the device during the first session.
5. Terminate and relaunch the app.

Pass criteria:

- no blank screen, crash, or frozen launch
- gateway visuals render correctly
- app relaunches into a sane state

## P0-Device-002: Manual wallet entry

Goal:

- verify strict address entry behavior on real keyboard/input conditions

Steps:

1. Paste a known-good EVM address.
2. Submit.
3. Repeat with leading/trailing spaces.
4. Repeat with mixed case.
5. Repeat with an invalid address.
6. Repeat with ENS text.

Pass criteria:

- valid addresses normalize and activate correctly
- invalid input fails with understandable feedback
- ENS remains explicitly rejected unless a task is specifically testing later ENS flows

## P0-Device-003: QR scan flow

Goal:

- verify camera permission, scan, validation, and dismissal behavior

Steps:

1. Open the scanner.
2. Deny camera permission, verify failure messaging.
3. Re-open and allow permission.
4. Scan a valid wallet payload.
5. Scan an invalid/non-wallet payload.
6. Cancel and return to the gateway.

Pass criteria:

- permission handling is clear
- valid scans feed the same validation path as manual entry
- invalid scans fail safely
- scanner dismissal does not corrupt shell state

## P0-Device-004: Guest pass flow

Goal:

- confirm the guest shortcut still behaves like a real account selection path

Steps:

1. Enter through a guest pass.
2. Navigate Home, Search, Tokens, Music, and Receipts.
3. Relaunch the app.
4. Log out and re-enter another guest pass.

Pass criteria:

- guest entry reaches a usable shell
- no stale data leaks from the prior guest or account

## P0-Device-005: Shell and tab routing

Goal:

- validate root navigation on an actual device with real touch interactions

Steps:

1. Visit every root tab.
2. Open one detail route from Search or News.
3. Back out one level at a time.
4. Switch tabs rapidly.
5. Background and foreground the app while on a detail route.

Pass criteria:

- navigation stacks stay coherent
- back behavior unwinds correctly
- tab switches do not scramble routed state

## P0-Device-006: Account switching and scope reset

Goal:

- verify one of the most failure-prone shell behaviors

Steps:

1. Use account A and open a detail view.
2. Switch to account B.
3. Confirm detail stacks reset.
4. Switch chain scope.
5. Switch back to account A.
6. Remove the active account if that flow is available.

Pass criteria:

- routed detail state resets when account changes
- chain scope and visible data match the selected account
- no stale NFTs or holdings from another scope remain onscreen

## P0-Device-007: NFT refresh and degraded mode

Goal:

- confirm the app behaves well under real network conditions

Steps:

1. Refresh on a known-good wallet.
2. Observe loading and exit states.
3. Toggle network off during or before refresh.
4. Restore network and retry.
5. Repeat on a wallet with no NFTs if available.

Pass criteria:

- success, empty, and failure states are all intentional
- retry recovers when the network returns
- the shell remains interactive enough to navigate away

## P0-Device-008: Home surface QA

Goal:

- verify that Home feels like a deliberate dashboard rather than a stitched-together debug view

Steps:

1. Inspect the profile card and account summary.
2. Open the account switcher sheet.
3. Verify modules, shortcuts, and recent activity.
4. Use any pinned-link or quick-link actions present.
5. Return after backgrounding the app.

Pass criteria:

- no duplicated, stale, or placeholder-looking sections
- interactions update the visible state correctly

## P0-Device-009: Search flow

Goal:

- validate parser, history, routing, and no-results behavior

Steps:

1. Open Search from every entry point available.
2. Search for a wallet-like query, collection-like query, and nonsense query.
3. Verify search history recording.
4. Tap a result into detail.
5. Back out and clear/reset if supported.

Pass criteria:

- typed results route correctly
- no-results state is clear and not misleading
- history is scoped and sane

## P0-Device-010: ERC-20 holdings and token details

Goal:

- close the manual UI QA gap called out in P0 closeout

Steps:

1. Open the ERC-20 tab on a known-good account.
2. Observe first content, cached content, or degraded state.
3. Switch chain scope.
4. Switch account.
5. Open a token detail screen.
6. Relaunch and return to the token surface.
7. Trigger privacy reset and return again.

Pass criteria:

- holdings remain scoped correctly
- failed refreshes do not wipe useful cached state incorrectly
- token detail routing remains coherent
- privacy reset clears the expected token-local state

## P0-Device-011: Gas screen

Goal:

- validate supported and unsupported chain behavior

Steps:

1. Open Gas on a supported chain.
2. Switch to an unsupported or differently behaved chain if available.
3. Relaunch and revisit Gas.

Pass criteria:

- values are readable
- unsupported behavior is explicit
- stale values are not presented like fresh live data

## P0-Device-012: Music playback

Goal:

- validate the highest-risk real-device lifecycle surface

Steps:

1. Open Music on an account with playable audio NFTs.
2. Start playback.
3. Pause, resume, next, previous.
4. Lock the device while audio is active.
5. Background and foreground the app.
6. Switch tabs repeatedly during playback.
7. Trigger a track change before the previous load fully settles if possible.

Pass criteria:

- playback state stays correct
- the mini player and now-playing surfaces stay in sync
- no stale metadata, wrong track, or wedged controls appear

## P0-Device-013: Audio interruptions and route changes

Goal:

- catch the device-only bugs the simulator politely hides

Steps:

1. Start playback.
2. Connect and disconnect headphones or Bluetooth audio if available.
3. Trigger a phone-call-like interruption or use another audio app.
4. Resume Auralis.

Pass criteria:

- interruptions do not leave the engine in a broken state
- route changes do not strand the UI or audio session

## P0-Device-014: Playlists

Goal:

- verify persistence and editing behavior on touch hardware

Steps:

1. Create a playlist.
2. Add items.
3. Reorder items.
4. Remove items.
5. Relaunch the app.

Pass criteria:

- validation, ordering, and persistence all behave correctly

## P0-Device-015: Receipts and privacy reset

Goal:

- verify operational logging and reset seams in the actual shipped environment

Steps:

1. Exercise key flows: launch, account change, chain change, refresh, search, external link.
2. Open Receipts and confirm entries exist.
3. Use the privacy reset flow in Settings.
4. Revisit Receipts, Search, Tokens, and any cache-backed surfaces.

Pass criteria:

- receipts append during normal use
- reset clears the intended local state
- the app remains healthy after reset and can start logging again

## P0-Device-016: External links and return path

Goal:

- validate outbound trust-labeled actions

Steps:

1. Open an external NFT link such as OpenSea if present.
2. Return to the app.
3. Repeat from another NFT or route.

Pass criteria:

- the correct destination opens
- returning does not break navigation or playback state

## P0-Device-017: Deep links

Goal:

- verify warm and cold launch behavior

Steps:

1. Trigger a supported deep link while the app is open.
2. Trigger a supported deep link from a terminated state.
3. Trigger an invalid deep link.

Pass criteria:

- valid links route once shell state is ready
- invalid links fail safely

## P0-Device-018: Rotation, Dynamic Type, and appearance

Goal:

- catch obvious physical-device presentation failures

Steps:

1. Test the default text size.
2. Increase Dynamic Type.
3. Check portrait and landscape if the app supports both.
4. Check light and dark appearance if supported.

Pass criteria:

- no clipped primary content
- buttons remain tappable
- chrome and cards remain readable

## Severity rubric

- `Blocker`: crash, stuck flow, corrupted scope, broken playback, unrecoverable navigation, privacy-reset failure
- `Major`: incorrect data shown, repeated failure in a core flow, severe layout break, wrong destination, unusable control
- `Minor`: polish issue, small visual defect, awkward spacing, inconsistent copy, one-off stale label without data corruption

## Final test report template

- build tested:
- devices tested:
- accounts/chains tested:
- blocker bugs:
- major bugs:
- minor bugs:
- deferred issues:
- go / no-go:
