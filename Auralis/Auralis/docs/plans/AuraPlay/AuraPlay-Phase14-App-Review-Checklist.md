# AuraPlay Phase 14 - App Review Checklist

Updated: 2026-07-25

## Automated / Code-Side Status

| Area | Status | Evidence |
| --- | --- | --- |
| App build | Passed | Xcode build-for-testing succeeded on 2026-07-25. |
| App fast test plan | Passed | `Auralis-Fast`: 588 passed, 51 skipped, 0 failed. |
| Music package tests | Passed | `MusicFeature`: 113 tests passed. |
| Media core tests | Passed | `AuraPlayMediaCore`: 37 tests passed. |
| Video engine tests | Passed | `AuraPlayVideoEngine`: 77 tests passed. |
| Privacy manifest tests | Covered by app test plan | Existing `AuraPlayPrivacyManifestTests` remains in the app-hosted suite. |

## Submission Checklist

| Item | Status | Notes |
| --- | --- | --- |
| Privacy manifest | Needs final human review | Current tests cover expected manifest contract; re-check against latest Apple upload warnings before archive. |
| Permission strings | Needs final human review | `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, URL schemes, and wallet query schemes should be read against final UI copy. |
| Background audio | Needs device sign-off | `UIBackgroundModes = audio` must be matched by real background playback behavior. |
| Wallet posture | Needs reviewer note | Submission notes should say the app is read-only, does not request private keys/seed phrases, and has no marketplace/trading. |
| Screenshots/previews | Pending | Capture after final device QA on the target build. |
| Age rating | Pending | Review NFT/crypto-adjacent content wording and media playback content. |
| Known limitations | Documented separately | See `AuraPlay-Phase14-Known-Limitations.md`. |

## App Review Note Draft

Auralis uses wallet addresses to discover and play media associated with public NFT metadata. The app does not request private keys or seed phrases and does not provide marketplace, trading, token sale, or asset-transfer functionality. Background audio is used only for user-initiated media playback.

