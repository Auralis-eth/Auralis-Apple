# AuraPlay Phase 14 - Settings, Accessibility, and Hardening Plan

7 Tickets - 17 hrs Total Estimate - v1.0 - Updated July 26, 2026

## Phase Purpose

Close the last ship-readiness gaps around AuraPlay without pretending Phase 14 is a greenfield feature phase.

The older April version of this phase had the right broad shape: settings polish, accessibility, privacy controls, error hardening, performance measurement, App Store readiness, and final regression sign-off. The details were stale. The current codebase already has a real `SettingsView`, live AuraPlay audio tuning controls, local privacy reset plumbing, typed playback errors, privacy-manifest tests, bundle-contract tests, Library/Player UI, local search and intelligence seams, playlists, playback-position persistence, and tombstone-backed Smart Resume.

This plan is therefore a hardening and truth-alignment pass over existing code, not a request to rebuild completed phases or introduce parallel abstractions.

## Current Baseline

Already available:

- Settings surface: `Auralis/Auralis/Aura/Settings/SettingsView.swift`.
- Settings-backed AuraPlay controls: EQ preset, 10-band custom EQ, loudness normalization, Download for offline, AutoMix crossfade, default shuffle/repeat, default video playback speed, cache usage/cap/clear-cache controls, Smart Shuffle, provider debug status in DEBUG, and Clear Local Privacy Data.
- Playback runtime seam: `AuraPlayPlaybackRuntime` over `PlaybackOrchestrator`, with transient playback warnings and recovery status.
- Playback error domains: `MusicFeature.AuraPlayError` and `AuraPlayMediaCore.AuraPlayError`.
- Privacy reset seam: `PrivacyResetService.resetLocalPrivacyData()` with `PrivacyAssembly` composition and `PrivacyResetServiceTests` coverage.
- App metadata: `Info.plist` declares background audio, URL schemes, wallet query schemes, `NSCameraUsageDescription`, and `NSPhotoLibraryUsageDescription`.
- Privacy manifest: `PrivacyInfo.xcprivacy` declares UserDefaults and file-timestamp accessed API categories, covered by `AuraPlayPrivacyManifestTests`.
- Search and intelligence seams: `AuraPlaySearchCoordinator`, `AuraPlaySemanticSearching`, `AuraPlayEmbeddingService`, `AuraPlayPlaylistService`, `AuraPlayRecommendationProviding`, `AuraPlayIntelligenceSettings`, and Phase 13 hosted tests.
- Regression coverage is spread across `AuralisTests`, `MusicFeatureTests`, `AuraPlayMediaCoreTests`, and `AuraPlayVideoEngineTests`; there is no separate `AuraPlayIntegrationTests` target.

Names from the April ticket set that should not be used as if they exist:

- `AppError` / `AppErrorBoundary` as an app-wide umbrella.
- `AuraPlaySchemaV2` or a formal migration plan as missing work. Phase 14 added `AuraPlaySchemaV1`, `AuraPlaySchemaV2`, and `AuraPlayMigrationPlan`.
- Generic `MediaItem`, `PlaybackState`, or `Playlist.aiGenerated`. Current names are `AuraPlayMediaItem`, `AuraPlayPlaybackPositionState`, `AuraPlayPlaylist.isSmart`, and `AuraPlayPlaylist.smartQueryData`.
- Per-phase `AuraPlayIntegrationTests` suites for Phases 1 through 13.

## Phase Gate

Phase 14 passes only when the final release artifacts tell the same story as the app:

- Settings exposes only controls backed by live storage/runtime seams.
- Manual accessibility, hardware playback, privacy, and App Review audits are completed and documented.
- Automated regression suites pass in the lanes that actually exist.
- Any misses that cannot be fixed within the phase are captured as explicit release notes or follow-up tickets with severity and owner.

## Ticket Summary

| ID | Title | Type | Priority | Estimate | Depends |
| --- | --- | --- | --- | --- | --- |
| P14-001 | Settings completion audit over existing `SettingsView` | TASK | P0 | 2.5 hrs | Phase 6/8/10/13 runtime settings |
| P14-002 | Accessibility audit across AuraPlay surfaces | TASK | P0 | 3 hrs | Phase 9/10/11/13 UI surfaces |
| P14-003 | Privacy reset and user-facing privacy controls audit | TASK | P1 | 2 hrs | Existing `PrivacyResetService`, Settings |
| P14-004 | Error presentation hardening and raw-error audit | TASK | P0 | 2.5 hrs | Current playback/search/provider error paths |
| P14-005 | Performance and hardware profiling pass | TASK | P1 | 2.5 hrs | Full assembled AuraPlay path |
| P14-006 | App Store readiness: manifest, permissions, and review checklist | TASK | P0 | 2 hrs | Current `Info.plist`, privacy manifest, bundle tests |
| P14-007 | Final regression and release sign-off artifacts | TASK | P1 | 2.5 hrs | Existing automated suites and device QA docs |

## P14-001 - Settings completion audit over existing `SettingsView`

Priority: P0  
Estimate: 2.5 hrs

### Description

Audit and finish the existing Settings surface. Do not create a second AuraPlay settings screen and do not duplicate preference storage. The current `SettingsView` already hosts AuraPlay audio tuning, Smart Shuffle, provider debug status, and privacy reset.

### Technical Notes

- Treat `SettingsView` as the owner of the app-visible Settings screen.
- Verify each existing binding maps to the live storage/runtime key it claims to control:
  - `AuraPlayAudioSettings.eqPresetDefaultsKey`
  - `AuraPlayAudioSettings.normalizationEnabledDefaultsKey`
  - `AuraPlayAudioSettings.crossfadeDurationDefaultsKey`
  - `AuraPlayAudioSettings.downloadForOfflineDefaultsKey`
  - `AuraPlayIntelligenceSettings.smartShuffleEnabledDefaultsKey`
  - `AuraPlayPlaybackPreferenceSettings.shuffleModeDefaultsKey`
  - `AuraPlayPlaybackPreferenceSettings.repeatModeDefaultsKey`
  - `PlaybackSpeedController.preferenceKey`
  - `AuraPlayCacheSettings.diskCapBytesDefaultsKey`
- Keep runtime-backed controls routed through `AuraPlayPlaybackRuntime` where available so changes reflect immediately during playback.
- Repeat/shuffle defaults, playback speed, cache cap, cache usage display, and clear-cache controls now have real app/runtime seams. Preserve those seams rather than adding shadow storage.
- Keep DEBUG-only provider configuration under `#if DEBUG`; do not leak developer diagnostics into release builds.
- Register any new Settings controls in `AuraUI/Sources/AuraUI/A11yID.swift` before UI tests depend on them.

### Acceptance Criteria

- Existing Settings controls read from and write to the current keys and update the runtime where applicable.
- No new `@AppStorage` keys are introduced unless a real owning feature also reads them.
- Any missing cache/repeat/shuffle/speed controls are either implemented against existing seams or documented as follow-up gaps.
- DEBUG-only diagnostics are absent from release builds.
- New or changed controls have accessibility labels/hints and registered identifiers when automation needs them.

## P14-002 - Accessibility audit across AuraPlay surfaces

Priority: P0  
Estimate: 3 hrs

### Description

Run a full accessibility pass across current AuraPlay UI surfaces, extending the spot checks already called out in `AuraPlay-UI-Design-Audit-Checklist.md` and `AuraPlay-Physical-Device-QA-Suite.md`.

### Technical Notes

- Audit current AuraPlay surfaces, not imagined April screens: Library, collection/creator/detail flows, mini-player, `AuraPlayPlayerView`, Up Next, audio controls sheet, playlist sheets, More Like This, Playlist Playground, Search/intelligence entry points, and `SettingsView`.
- Verify VoiceOver labels, hints, traits, and reading order for all interactive controls and major state messages.
- Verify Dynamic Type at the largest accessibility sizes. Critical information cannot overlap or disappear; accepted truncation points must be listed in the findings document.
- Verify Reduce Motion behavior for the mini-player/player transition, marquee text, decorative playback motion, and any state-change animation. Use `AuraMotionPolicy` or local `accessibilityReduceMotion` environment values rather than direct ad hoc animation checks.
- Verify Reduce Transparency fallback for artwork-heavy or glass/blur surfaces. `AuraPlayPlayerView` already documents an opaque fallback for audio backgrounds; confirm the actual UI matches that contract.
- Spot-check custom-colored badges, warnings, and artwork scrims for contrast against the actual app backgrounds.
- Produce a findings document with resolved issues and any accepted limitations.

### Acceptance Criteria

- Accessibility Inspector reports no missing labels on audited AuraPlay controls.
- VoiceOver reading order follows visual and task order.
- Critical text and primary actions remain usable at largest accessibility Dynamic Type sizes.
- Custom motion and transparency-heavy visuals degrade correctly.
- A committed findings document lists every issue found, fix status, and accepted limitation.

## P14-003 - Privacy reset and user-facing privacy controls audit

Priority: P1  
Estimate: 2 hrs

### Description

Audit the existing local privacy reset and privacy copy for accuracy. The app already has `Clear Local Privacy Data`; this ticket verifies that it clears what the UI promises and that the product explains local data handling honestly.

### Technical Notes

- Use `PrivacyResetService.resetLocalPrivacyData()` as the reset seam.
- Verify reset coverage against current storage boundaries:
  - main SwiftData data covered by the app reset service
  - AuraPlay store cleanup through the AuraPlay persistence reset contract
  - receipts and receipt integrity heads
  - search history and CoreSpotlight domains used by app/AuraPlay search
  - ENS cache, gas cache, token holdings, pinned home actions, and active shell selection
  - credentials/session entries owned by account and wallet-connect services
- Keep `SettingsView` responsible for notifying the shell after reset so the visible session does not remain signed in after storage cleanup.
- Do not add a separate `Disconnect All Wallets` control unless the current account/wallet services expose a real all-wallet removal path with Keychain/session cleanup. If that seam does not exist, document the gap separately.
- Add or update static privacy copy in Settings only if it can be verified against actual behavior: public NFT metadata/media gateways, on-device search/intelligence where applicable, no analytics/tracking if true, read-only wallet sessions, no private-key entry.

### Acceptance Criteria

- Reset tests prove the current local data stores named by Settings are cleared or intentionally preserved with rationale.
- The visible shell state logs out or returns to an unauthenticated/neutral state after reset succeeds.
- Privacy copy does not make aspirational claims that code does not support.
- Any absent all-wallet disconnect behavior is tracked as a separate follow-up rather than faked with partial reset logic.

## P14-004 - Error presentation hardening and raw-error audit

Priority: P0  
Estimate: 2.5 hrs

### Description

Audit user-visible error handling across AuraPlay and adjacent Music tab flows. The goal is not to introduce a speculative app-wide `AppError` umbrella; it is to ensure actual thrown errors are mapped before they reach users.

### Technical Notes

- Enumerate current user-facing error domains and paths:
  - `MusicFeature.AuraPlayError`
  - `AuraPlayMediaCore.AuraPlayError`
  - `ProviderAbstractionError` / NFT provider failures where they affect AuraPlay sync or search
  - playback warnings and recovery messages in `AuraPlayPlaybackRuntime`
  - video load failures from `AuraPlayVideoWireframeView` / `AuraPlayVideoEngine`
  - Settings privacy-reset failure messages
  - Search assistant, Spotlight, and embedding availability failures
- Grep for raw `error.localizedDescription`, `String(describing: error)`, or framework strings reaching SwiftUI `Text`, alerts, banners, toasts, or observable presentation state.
- Logging may include technical error descriptions when appropriate; user-visible copy should go through product-facing mapping functions or typed error descriptions that have been reviewed.
- Add a top-level generic error presenter only if there is already a shared routed-error stream such as `AppRouter` / `AppRouteError` that can be reused without inventing a new global error bus.
- Produce a findings document mapping each actual error path to its UI presentation or intentional silent/log-only behavior.

### Acceptance Criteria

- Every current AuraPlay-facing error path has reviewed UI copy, recovery copy, or documented silence rationale.
- No raw stack traces, raw framework messages, or debug strings are shown directly to users.
- Simulated playback, privacy-reset, sync, and search failures land in the expected UI states without freezing navigation.
- The findings document names the source path, presentation path, and fix/rationale.

## P14-005 - Performance and hardware profiling pass

Priority: P1  
Estimate: 2.5 hrs

### Description

Measure the assembled AuraPlay experience on the devices and data sizes that matter, then fix small obvious issues or record concrete follow-ups for larger misses.

### Technical Notes

- Cold launch: measure launch to interactive shell/Music path with a moderate wallet-scoped library. Record device, iOS, build config, account fixture, and whether the AuraPlay store was warm or cold.
- Library scroll: verify the Library grid/list stays smooth with a 500+ item fixture or real wallet. Pay attention to artwork decode, query paging, and grouped-index invalidation.
- Search latency: measure end-to-end AuraPlay Search / intelligence entry points through UI, not only isolated service calls.
- Memory: profile combined playback plus background sync and inspect store/query memory growth.
- Battery and hardware playback: execute the relevant `AuraPlay-Physical-Device-QA-Suite.md` audio/video sections, including background audio, route changes, interruptions, PiP/AirPlay where available, poor-network playback, offline launch, and one-hour battery run.
- Document results. Fix small local issues in-scope; create follow-up tickets for work that needs architecture changes, new fixtures, or more hardware time.

### Acceptance Criteria

- Measurements exist for cold launch, library scroll, search latency, memory, and battery/hardware playback.
- Any budget miss includes severity, reproduction setup, and remediation owner.
- No unresolved blocker remains undocumented.
- The physical-device QA suite result is linked or summarized from the Phase 14 findings artifact.

## P14-006 - App Store readiness: manifest, permissions, and review checklist

Priority: P0  
Estimate: 2 hrs

### Description

Run the final compliance pass against the actual app metadata and current code usage.

### Technical Notes

- Audit `Auralis/Auralis/PrivacyInfo.xcprivacy` against current required-reason API use in the app and package graph. Current app declarations include UserDefaults and file timestamp categories; confirm they remain necessary and sufficient.
- Keep `AuraPlayPrivacyManifestTests` updated with any manifest changes.
- Review `Info.plist` permission strings for accuracy:
  - `NSCameraUsageDescription` for QR/wallet scanning and any other actual camera path
  - `NSPhotoLibraryUsageDescription` for actual media/artwork selection paths
  - `UIBackgroundModes` audio for real background playback, not generic background execution
  - URL schemes and wallet query schemes used by wallet/deep-link flows
- Confirm wallet connection UI remains read-only and does not request private keys, seed phrases, or trading/marketplace authorization.
- Confirm App Review notes explain the no-marketplace/no-trading posture if the submission references NFTs.
- Produce an App Review checklist document covering privacy manifest, permission strings, background audio, wallet posture, screenshots/preview accuracy, age rating considerations, and known limitations.

### Acceptance Criteria

- Privacy manifest declarations match audited code usage and tests pass.
- Permission strings are specific, accurate, and tied to real app features.
- Wallet connection review confirms no private-key or seed entry path.
- Background audio is justified by real playback behavior.
- A committed App Review checklist exists.

## P14-007 - Final regression and release sign-off artifacts

Priority: P1  
Estimate: 2.5 hrs

### Description

Assemble the actual automated and manual sign-off process for v1. Do not invent non-existent phase-specific integration targets; use the test lanes that exist and document any missing lanes as release-process follow-up.

### Technical Notes

- Automated suites to run or explicitly record as not run with reason:
  - active Xcode scheme tests for `AuralisTests`
  - `MusicFeatureTests`
  - `AuraPlayMediaCoreTests`
  - `AuraPlayVideoEngineTests`
  - UI smoke/accessibility tests where available
  - SwiftLint / build lanes used by CI
- Confirm specific high-value existing suites are included: Phase 8 playback orchestration, Phase 13 intelligence hosted tests, privacy reset, privacy manifest, bundle contract, cache launch configuration, search/embedding, Spotlight support, deep-link parser, persistence spine/wave tests.
- Migration note: AuraPlay persistence now uses `AuraPlayMigrationPlan`; keep the V1-to-V2 upgrade-path test in the release gate and add future migration stages instead of editing the V1 schema.
- Produce a master QA checklist consolidating the existing physical-device suite, UI/design audit checklist, accessibility findings, App Review checklist, and cold-install-to-first-playback script.
- Compile known v1 limitations from `AuraPlay-Gaps.md`, `AuraPlay-Future-Work.md`, and phase docs into release notes.

### Acceptance Criteria

- The real automated suites pass or have documented blockers with owners.
- A master device/manual QA checklist exists and references the current physical-device and UI/design audit docs.
- Cold-install-to-first-playback walkthrough is scripted and signed off on a physical device before release.
- Schema migration status is truthful: either covered by a real versioned-schema test or documented as flat-schema release debt.
- Known limitations are consolidated and cross-referenced against the living gap/future-work docs.

## Documentation Outputs

Phase 14 should produce or update these artifacts:

- `AuraPlay-Phase14-Settings-Accessibility-Hardening-Plan.md` - this plan.
- `AuraPlay-Phase14-Accessibility-Findings.md` - audit findings and fixes.
- `AuraPlay-Phase14-Error-Presentation-Audit.md` - error coverage matrix.
- `AuraPlay-Phase14-App-Review-Checklist.md` - App Store readiness checklist.
- `AuraPlay-Phase14-Master-QA-Checklist.md` - final manual and automated sign-off rollup.
- `AuraPlay-Phase14-Known-Limitations.md` - consolidated release limitations.
- `AuraPlay-Status.md` - one-line updates for completed Phase 14 work.
- `AuraPlay-Gaps.md` - only unresolved gaps that survive the phase.

## Validation Notes

Doc-only updates do not require a build. Implementation tickets that touch SwiftUI or services should use fast file diagnostics first, then the active Xcode test/build lanes appropriate to the touched subsystem.

For UI work, verify with Dynamic Type, VoiceOver, Reduce Motion, and Reduce Transparency. For playback or battery claims, simulator validation is insufficient; use physical hardware and record the exact device/iOS/build.
