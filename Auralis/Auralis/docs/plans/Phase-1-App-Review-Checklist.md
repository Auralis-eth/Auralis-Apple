# Phase 1 — App Review Checklist (Mission Control / Operator Console)

Pre-submission checklist for the Phase 1 release path (the Mission Control "Ops" tab over the shared
`RuntimeHost`). Author/owner works each item and records a result. This is the App-Review gate called
for by `OperatorConsole-Ship-Readiness.md` → "Ship blockers." Companion gates:
`Phase-1-Physical-Device-QA-Suite.md` (device), `P0-UI-Test-QA-Suite.md` (automated),
`Phase-1-Known-Limitations.md` (disclosed limitations).

Status of the *feature surface*: **code-complete, unit/snapshot-verified, app builds green.** The items
below are the human/device/policy gates that a compiler cannot close.

Mark each: ✅ pass · ❌ fail (link finding) · ⚠️ N/A-with-reason · ⬜ not started.

## Build & submission hygiene
- [ ] Release configuration builds and archives clean (note: `AppTabBarVisibility.live` is `.all` in
      DEBUG, `.release` in Release; Mission Control ships in both).
- [ ] Version + build number bumped; changelog/what's-new drafted.
- [ ] No debug-only affordances leak into Release (e.g. `-ui-testing-mission-control-fixtures`,
      `#if DEBUG seedForSnapshot(...)`).
- [ ] dSYMs uploaded; no missing-symbol warnings.

## Privacy & data (App Privacy "nutrition label")
- [ ] Privacy manifest / App Privacy answers match reality: on-device receipts, artifacts, execution
      records, leases; no undisclosed collection.
- [ ] `Info.plist` usage-description strings present for every permission actually requested.
- [ ] "Clear Local Privacy Data" (Settings) fully clears operator/runtime stores — verified via
      **MC-Device-012**.
- [ ] Data classification consistent with ADR-003.

## Capabilities & background modes
- [ ] `UIBackgroundModes` / `BGTaskSchedulerPermittedIdentifiers` (`com.auralis.runtime.refresh`) are
      declared and justified; background firing verified via **MC-Device-010**.
- [ ] Keychain usage (SE signing key persistence) reviewed; **MC-Device-011** passed.
- [ ] No private API usage; no undeclared entitlements.

## Governance / safety review (the differentiating surface)
- [ ] Kill switch ("Pause all operator activity") demonstrably halts new and scheduled work
      (**MC-Device-002**).
- [ ] Crypto Observe boundary blocks wallet-affecting steps with a denial receipt (**MC-Device-009**,
      ADR-010); Assist/Operate surfaces describe what they allow in plain language.
- [ ] Approvals write durable, correct receipts (approve/reject resolve, defer stays pending) across
      relaunch (**MC-Device-003**).
- [ ] Receipt chain verifies end-to-end; exports carry `signature` + `signerPublicKey`
      (**MC-Device-005**).

## Accessibility
- [ ] On-device VoiceOver pass across the 14 Mission Control sections (code audit done 2026-08-13;
      device sweep is the residual — see `Phase-1-Known-Limitations.md` L-04).
- [ ] Dynamic Type: layouts hold at accessibility sizes.
- [ ] Sufficient contrast: status is never conveyed by color alone.

## Content, metadata & guideline fit
- [ ] Screenshots reflect the shipping console (14 sections), not seeded debug fixtures.
- [ ] App description accurately presents the explicit user-triggered, governed goal runner and does not
      claim unattended/full autopilot, autonomous multi-agent execution, or other deferred Phase 2 authority.
- [ ] Crypto/wallet framing complies with the applicable App Review guidelines for the target markets.
- [ ] Support URL, marketing URL, and age rating set.

## Known limitations disclosed
- [ ] Every item in `Phase-1-Known-Limitations.md` is either resolved or intentionally disclosed; no
      undisclosed `Blocker`/`Major` from the device QA suite remains open.

## Sign-off
- Owner:
- Date:
- Build submitted:
- Go / No-go:
