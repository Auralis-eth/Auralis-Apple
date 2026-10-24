# P0 UI Test QA Suite

Generated: May 23, 2026
Last refreshed: August 17, 2026
Scope: Automated UI and accessibility-audit coverage for Phase 1 and Phase 2 accessibility readiness,
including the Mission Control operator console.

This suite is the automated companion to `P0-Physical-Device-QA-Suite.md` and
`Phase-1-Physical-Device-QA-Suite.md`. It does not replace real-device QA. It catches regressions that
XCTest can see: missing screens, broken identifiers, unreachable controls, and iOS 17+ accessibility
audit failures.

## Current Record

Last checked: August 17, 2026

- Xcode `Auralis` build: passed
- UI test target: **present** — `AuralisUITests` (`AccessibilityAuditUITests.swift`)
- `performAccessibilityAudit` references: **present** — used in `performAudit(in:)`, guarded with
  `if #available(iOS 17.0, *)` and auditing `.all.subtracting(.contrast)`; a hand-rolled
  `performLegacyAudit(in:)` covers pre-iOS 17 runtimes
- Screens with automated audit coverage: Gateway (+ validation error, scanner fallback), Home (+ large
  text, account-switcher removal), News Feed (+ NFT action menu), Search (+ populated history), Gas,
  Music (+ Now Playing), NFTs (+ external-link confirmation), Receipts (+ receipt detail), Settings
  privacy reset
- Mission Control coverage: `testMissionControlOperatorConsoleSmoke` (pause toggle + section navigation
  + operator run + artifact detail), `testMissionControlApprovalInboxOpensLinkedReceiptDetail`,
  `testMissionControlArtifactBrowserOpensRelatedReceiptDetail`,
  `testMissionControlArtifactLifecycleControlsAreReachable`
- Known coverage gaps: no `performAccessibilityAudit` call yet inside the Mission Control sections (the
  MC tests assert reachability/identifiers but do not run the audit); several tests `XCTSkip` when the
  fixture does not seed the required state (Now Playing session, runnable operator, NFT action menu)

Result: The automated accessibility gate is **partially green** — the historical "no-go / no UI tests"
record is stale and has been corrected. Remaining before a full go: add `performAccessibilityAudit` to
the Mission Control sections and remove the fixture-driven skips by seeding deterministic state.

> **Note:** the prior "503 passed / UI test files: none / no `performAccessibilityAudit`" record (dated
> May 23, 2026) was stale — a UI test target with accessibility-audit coverage now exists, including
> Mission Control smoke tests. Re-run the active test plan and record fresh counts here.

## Exit Rule

The UI test QA gate passes only when:

- a UI test target is present in the active `Auralis` test plan
- the tests launch the app into deterministic states for gateway, Home, News Feed, Search, Settings, and Music where feasible
- iOS 17+ tests call `performAccessibilityAudit` on the critical screens
- tests verify the identifiers and controls needed by the physical-device accessibility script
- the full active test plan passes after the UI test suite is added
- any audit failures are filed against `ACCESSIBILITY_TICKETS.md` or a tracked follow-up with release risk

## Required UI Test Coverage

### P0-UI-001: Gateway accessibility smoke

Goal:

- verify first-launch gateway controls are present and accessible enough for automated audit coverage

Steps:

1. Launch the app with a clean or reset UI-test state.
2. Wait for the gateway or account-entry surface.
3. Verify wallet entry, QR scanner entry, submit action, validation path, and guest pass controls are discoverable by accessibility identifier or accessible label.
4. On iOS 17+, run `performAccessibilityAudit` for the current screen.

Pass criteria:

- no required gateway control is missing
- invalid address feedback appears after a bad submission
- iOS 17+ accessibility audit reports no unresolved blocker findings

### P0-UI-002: Home accessibility smoke

Goal:

- verify Home shell controls, launcher actions, profile/account management, sparse state actions, and image preview controls remain discoverable

Steps:

1. Launch into a deterministic account state.
2. Navigate to Home.
3. Verify profile/account management, launcher shortcuts, pinned action controls, image preview, and logout controls exist.
4. On iOS 17+, run `performAccessibilityAudit` for Home.

Pass criteria:

- Home primary actions are reachable by identifier or accessible label
- no icon-only Home action regresses to an unnamed control
- iOS 17+ accessibility audit reports no unresolved blocker findings

### P0-UI-003: News Feed accessibility smoke

Goal:

- verify News Feed toolbar and NFT card actions stay accessible after the nested-button fix

Steps:

1. Launch into an account state with NFTs or a controlled empty/provider state.
2. Navigate to News Feed.
3. Verify Sort NFTs and Refresh NFTs controls exist.
4. Verify empty/error actions or NFT card open/copy actions are reachable depending on fixture state.
5. On iOS 17+, run `performAccessibilityAudit` for News Feed.

Pass criteria:

- sort and refresh controls are findable by name
- NFT card primary action and copy action are exposed without nested interactive controls blocking access
- iOS 17+ accessibility audit reports no unresolved blocker findings

### P0-UI-004: Search accessibility smoke

Goal:

- verify the search field keeps a stable label and history/result rows retain usable actions

Steps:

1. Navigate to Search.
2. Verify `search.queryField` exists.
3. Type a wallet, token, NFT, and invalid query where deterministic fixtures allow it.
4. Verify local results, no-results state, history delete, and clear-all controls where applicable.
5. On iOS 17+, run `performAccessibilityAudit` for Search.

Pass criteria:

- query field remains reachable by identifier and label
- history delete controls are reachable and destructive actions remain separate from row open actions
- iOS 17+ accessibility audit reports no unresolved blocker findings

### P0-UI-005: Settings privacy reset accessibility smoke

Goal:

- verify destructive privacy reset flow remains accessible and announces visible state changes through UI feedback

Steps:

1. Navigate to Settings.
2. Verify Clear Local Privacy Data exists.
3. Open the confirmation dialog, cancel once, then open it again and confirm in a reset-safe test state.
4. On iOS 17+, run `performAccessibilityAudit` for Settings before confirmation.

Pass criteria:

- reset button and confirmation buttons are reachable
- success or failure feedback appears after reset action
- iOS 17+ accessibility audit reports no unresolved blocker findings

### P0-UI-006: Music accessibility smoke

Goal:

- verify Phase 2 music accessibility fixes remain covered where the music surface is available in the test state

Steps:

1. Navigate to Music.
2. Verify mini-player or empty/library state controls are reachable.
3. If recently played data is available, verify Play, Start Over, and Remove actions remain accessible.
4. On iOS 17+, run `performAccessibilityAudit` for Music.

Pass criteria:

- mini-player opens Now Playing through semantic button behavior or an equivalent reachable element
- recently played secondary actions are not context-menu-only in accessible flows
- iOS 17+ accessibility audit reports no unresolved blocker findings

### P0-UI-007: Mission Control operator console accessibility + reachability

Goal:

- verify the Phase 1 operator console (the "Ops" tab, `tab.missionControl`) exposes its governance
  controls and section navigation to automation and assistive tech

Steps:

1. Launch with `-ui-testing-authenticated` (and `-ui-testing-mission-control-fixtures` for seeded
   approvals/artifacts).
2. Select the "Ops" tab and confirm `missionControl.modeSection` is present.
3. Toggle `missionControl.pauseToggle` and confirm the paused state text and resume path appear.
4. Navigate to Receipts, Routines, Operators, Approvals, and Artifacts via the sidebar or
   `Mission Control section` picker and confirm each section's identifier resolves.
5. Open a seeded approval and confirm it links to `missionControl.receipt.detail`.
6. Open a seeded artifact and confirm `missionControl.artifact.detail`, plus that
   `missionControl.artifact.export` and `missionControl.artifact.supersede` are reachable.
7. On iOS 17+, run `performAccessibilityAudit` for the Home, Approvals, Receipts, and Artifacts
   sections. *(Not yet implemented — see Known coverage gaps.)*

Pass criteria:

- the pause toggle, section navigation, and lifecycle controls are reachable by identifier
- approval → receipt and artifact → receipt links resolve to the correct detail
- iOS 17+ accessibility audit reports no unresolved blocker findings on the covered sections
- fixture-dependent steps that cannot seed state `XCTSkip` with a clear reason rather than failing

## Implementation Notes

Use XCTest/XCUIAutomation for this suite. Swift Testing remains preferred for unit and integration tests, but UI automation still belongs in XCTest.

Suggested conventions:

- name the target `AuralisUITests`
- keep launch arguments explicit, for example `-uiTesting`, `-resetLocalState`, and fixture selectors for account/NFT state
- use stable accessibility identifiers for elements whose labels are localized or dynamic
- query by visible labels for Voice Control-sensitive controls such as `Sort NFTs`, `Refresh NFTs`, and `Query`
- guard `performAccessibilityAudit` with `if #available(iOS 17.0, *)`
- keep QR scanner camera behavior in physical-device QA; automated UI tests can verify the scanner entry point and permission-denied copy only if the test environment supports it reliably

## Report Template

- build tested:
- simulator/device runtime:
- iOS version:
- UI test target present: yes/no
- `performAccessibilityAudit` screens covered:
- tests passed:
- tests failed:
- unresolved accessibility audit failures:
- deferred manual-only checks:
- go / no-go:
