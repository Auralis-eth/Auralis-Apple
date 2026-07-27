# AuraPlay Phase 14 - Master QA Checklist

Updated: 2026-07-26

## Automated Gates

| Gate | Status | Result |
| --- | --- | --- |
| Xcode build-for-testing | Passed | 2026-07-25, 21.801 seconds |
| Xcode `Auralis-Fast` test plan | Passed | 639 total: 588 passed, 51 skipped, 0 failed |
| `MusicFeature` package | Passed | 113 tests passed |
| `AuraPlayMediaCore` package | Passed | 37 tests passed |
| `AuraPlayVideoEngine` package | Passed | 77 tests passed |
| AuraPlay cache settings focused tests | Passed | `cacheCapPreferenceIsClampedAndPersisted` and `clearUnpinnedCachePreservesPinnedAndActiveFiles` passed on 2026-07-26. |
| Phase 14 app-hosted focused tests | Passed | `playbackPreferenceSettingsRoundTripDefaultModes` and `resetLocalPrivacyDataInvokesEveryBoundary` passed on 2026-07-26. |
| All-wallet disconnect focused test | Passed | `disconnectAllWalletsRemovesAccountsAndClearsPrivacyData` passed on 2026-07-26. |
| AuraPlay migration and error presentation focused tests | Passed | `AuraPlayMigrationTests` and `AuraPlayErrorPresentationTests` passed via `swift test --disable-sandbox --package-path MusicFeature --filter 'AuraPlayMigrationTests\\|AuraPlayErrorPresentationTests'` on 2026-07-26. |

## Manual Device Gates

| Area | Status | Steps |
| --- | --- | --- |
| Cold install to first playback | Pending | Install release build, launch, connect/restore wallet, sync, open Music, start track, background app, resume. |
| Background audio | Pending | Lock screen, Control Center, interruptions, route changes, AirPods, AirPlay where available. |
| Video playback | Pending | Full-screen, PiP, AirPlay/external route, subtitles/audio descriptions, speed changes. |
| Offline/cache | Pending device sign-off | Automated cache settings coverage passes; still run download/offline item, airplane mode, relaunch, playback, and Settings clear-cache/privacy reset on device. |
| Accessibility | Pending | VoiceOver reading order, Dynamic Type, Reduce Motion, Reduce Transparency, contrast spot-check. |
| Search/intelligence | Pending | Representative local search, Smart Shuffle, More Like This, Playlist Playground if enabled. |
| Privacy reset | Pending device sign-off | Runner-safe orchestration coverage passes; still confirm shell state, local stores, search history, credentials, and receipts on a cold installed device build. |

## Cold-Install Walkthrough

1. Install a clean release-config build on a physical iPhone.
2. Launch and connect or restore a read-only wallet.
3. Confirm NFT/media sync finishes without raw technical errors.
4. Open Music and verify Library is populated.
5. Start audio playback, scrub, skip, background the app, then resume.
6. Open a video item, test full-screen/PiP if available, then return to Music.
7. Use Settings to change EQ/normalization/AutoMix and confirm runtime behavior remains stable.
8. Run Clear Local Privacy Data and verify the app returns to a neutral unauthenticated state.
