# P0 Launch And Smoke Checklist

Use this checklist as the release gate when Phase 0 is complete. The goal is not to admire the architecture. The goal is to catch the obvious breakages before users do.

## Exit Rule

Ship only when:

- every blocking item below is marked complete
- no active Xcode navigator errors remain
- the app builds cleanly on the intended shipping configuration
- the tester can run the core user journey without improvising around bugs

## Preflight

- [ ] Confirm the active scheme is `Auralis`
- [ ] Confirm the intended bundle identifier, version, and build number are correct
- [ ] Confirm required secrets/configuration for provider-backed flows are present
- [ ] Confirm the app launches on a clean install
- [ ] Confirm the app launches after deleting and reinstalling
- [ ] Confirm there are no active build errors or warnings that block release confidence

## First Launch

- [ ] Launch from a clean install reaches the expected gateway/onboarding state
- [ ] No blank screen, crash, frozen loading state, or layout corruption on first launch
- [ ] Background image, typography, and primary CTA render correctly on the launch path
- [ ] App can be terminated and relaunched without getting stuck in a bad state

## Account And Wallet Flows

- [ ] Manual address entry accepts a valid wallet address
- [ ] Invalid address entry fails safely with understandable feedback
- [ ] Demo/guest account flow still works
- [ ] QR scanner flow opens and dismisses cleanly
- [ ] Selecting an account updates the active account in the shell
- [ ] Switching accounts resets routed detail stacks as expected
- [ ] Removing the active account falls back safely or returns to onboarding cleanly
- [ ] Logout clears the active session without corrupting persisted account data
- [ ] Relaunch after logout returns to the expected state

## NFT Refresh And Persistence

- [ ] Refresh succeeds for a known-good wallet on the intended supported chain
- [ ] The loading view progresses and exits cleanly
- [ ] Refreshed NFTs appear in the correct account and chain scope
- [ ] Switching accounts does not leave stale NFTs from the previous scope on screen
- [ ] Switching chains does not leak NFTs between chain scopes
- [ ] Relaunch preserves the expected persisted NFT state
- [ ] Empty wallet state renders intentionally and does not look broken
- [ ] Provider failure states render useful messaging instead of silent failure
- [ ] Offline or rate-limited behavior fails safely and recovers on retry

## Home Tab

- [ ] Home tab loads without placeholder-looking broken sections
- [ ] Profile card shows the correct active address
- [ ] Avatar generation or fallback image behaves deterministically enough to feel intentional
- [ ] Account switcher sheet opens, closes, and applies selections correctly
- [ ] Gallery selection/regeneration flows do not produce stale or duplicated state

## News / NFT Browsing

- [ ] News feed loads for a wallet with NFTs
- [ ] Search/filter controls behave correctly
- [ ] Tapping an NFT opens the expected detail route
- [ ] Empty state for no NFTs looks correct
- [ ] External link actions open the correct destination
- [ ] Returning from external links leaves the app in a healthy state

## Routing And Deep Links

- [ ] Home-to-detail routing sends audio NFTs to Music and visual NFTs to NFT Tokens
- [ ] Back navigation unwinds one level at a time
- [ ] Deep links work after warm launch
- [ ] Deep links work after cold launch once shell state is ready
- [ ] Invalid deep links fail safely with error presentation instead of bad navigation state
- [ ] Receipt routing fails safely if full receipt support is not yet complete

## Gas

- [ ] Gas screen loads on supported chains
- [ ] Gas values render in a readable format
- [ ] Unsupported chain behavior is explicit and safe
- [ ] Cached or fallback gas behavior does not present obviously stale nonsense as live data

## Music

- [ ] Music tab loads without crashing when NFTs contain audio
- [ ] Selecting a playable NFT starts the expected playback flow
- [ ] Mini player appears when playback is active
- [ ] Now Playing screen opens and reflects the current track
- [ ] Pause, resume, next, and previous controls behave correctly
- [ ] Remote audio loading failure surfaces safely and does not wedge playback state
- [ ] Track changes do not reuse the wrong temp file or stale metadata
- [ ] Relaunch does not leave the audio engine in a broken state

## Playlists

- [ ] Create playlist flow works
- [ ] Playlist title trimming/validation works
- [ ] Add/remove/reorder items behaves correctly
- [ ] Playlist persistence survives relaunch

## Receipts And Internal Safety Nets

- [ ] Key receipt-producing flows still succeed without runtime errors
- [ ] Reset receipts flow clears receipts and allows fresh appends afterward
- [ ] No obvious receipt-sequencing corruption appears during manual verification

## UI Quality

- [ ] No obvious clipped text or broken layouts on the target device size
- [ ] Core screens remain usable in light/dark appearances if supported
- [ ] Accessibility labels exist for major interactive controls
- [ ] Buttons are tappable and do not rely on fragile gesture-only behavior for primary actions

## Stability

- [ ] Backgrounding and foregrounding the app does not corrupt shell state
- [ ] Rapid account switching does not produce stale content or crashes
- [ ] Rapid tab switching does not produce broken navigation stacks
- [ ] Repeated refresh attempts do not create duplicate persisted state

## Release Sign-Off

- [ ] Full tests already completed and reviewed
- [ ] Manual smoke pass completed on the intended release device
- [ ] Blocking bugs found during smoke pass are fixed or consciously deferred
- [ ] Deferred issues are documented with owner and follow-up plan
- [ ] Final go/no-go decision recorded

## Notes

- Record the device, OS version, app version/build, wallet/account used for testing, and any deferred issues here before shipping.
