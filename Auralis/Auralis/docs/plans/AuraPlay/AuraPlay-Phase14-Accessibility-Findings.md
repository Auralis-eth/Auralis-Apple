# AuraPlay Phase 14 - Accessibility Findings

Updated: 2026-07-26

## Scope

Audited from code and automated coverage:

- `SettingsView`
- AuraPlay Library cells and list/grid presentations
- `AuraPlayPlayerView`
- Up Next sheet
- Music detail, collection, creator, ecosystem routes
- Search/intelligence entry points covered by app-hosted tests

Manual VoiceOver, Accessibility Inspector, and physical-device Dynamic Type sweeps still require a human device pass before App Store submission.

## Findings

| ID | Area | Status | Finding | Resolution |
| --- | --- | --- | --- | --- |
| P14-A11Y-001 | Settings | Resolved in existing code | Settings controls expose semantic labels and use standard SwiftUI controls for toggles/sliders/actions. | Verified `SettingsView` has no live Xcode diagnostics. |
| P14-A11Y-006 | Settings playback/storage controls | Resolved in code | New playback defaults, video speed, cache usage, cache limit, and clear-cache controls use native controls with accessibility identifiers and explicit slider values/hints. | Verified `SettingsView` has no live Xcode diagnostics; device traversal still belongs to P14-A11Y-004. |
| P14-A11Y-002 | Library/Player snapshots | Resolved | Snapshot coverage previously depended on an external host renderer that crashed on this environment. | Replaced with a local `NSHostingView` PNG renderer and refreshed deterministic light/dark/Dynamic Type baselines. |
| P14-A11Y-003 | Dynamic Type | Partially verified | Library and player snapshots include an accessibility-size baseline, but this is macOS-host rendering. | Keep as automated regression. Run iOS device Dynamic Type before submission. |
| P14-A11Y-004 | VoiceOver reading order | Pending manual sign-off | Static code review cannot prove actual VoiceOver traversal order. | Run Accessibility Inspector over Library, Player, Settings, Playlist, More Like This, and search flows. |
| P14-A11Y-005 | Reduce Motion / Transparency | Pending manual sign-off | Codebase uses `AuraMotionPolicy` patterns, but visual behavior needs runtime verification. | Exercise reduced motion/transparency on device during master QA. |

## Accepted Limits

- Snapshot baselines are macOS-host images, not final iOS simulator pixels.
- Largest Dynamic Type is covered by a snapshot lane for the most important player/library surfaces, but not by a full UI automation crawl.
