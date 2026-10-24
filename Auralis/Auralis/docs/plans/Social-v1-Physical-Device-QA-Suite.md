# Social v1 - Two-Device Physical QA Suite

**Status:** Not run. The relay path is enabled in Debug and Release, but production readiness remains gated.
**Created:** 2026-08-21.
**Last reconciled with code:** 2026-10-22.
**Release rule:** This suite remains the stated gate for production-public Social v1. Contrary to the earlier intended
gate, `AURALIS_SOCIAL_RELAY_ENABLED` is currently `YES` in Debug and Release. That configuration does not count as QA
or release-risk signoff. No row has passed on hardware; live wallet-signature join, cross-device sync, reconnect replay,
ended-session enforcement, and privacy reset remain **unverified on hardware**.

**2026-08-21 note:** Phase 2 non-device implementation work added local event/outbox persistence, join challenge
validation, relay coordinator seams, and automated tests. This does **not** satisfy this physical QA suite; all
executable rows remain `Not run` until two real devices and two independently controlled wallet identities are used.

**2026-10-22 blocker:** The current wallet connector ownership seam returns a local Boolean and discards the signature.
Device A therefore cannot independently verify Device B's join proof; B remains `.pending` on A and B-authored binding
votes and queue mutations fail closed. `SOC-Device-002`, `007`, `008`, `009`, and `010` are blocked until portable
proof is implemented as described in `P0-Future-Work.md`, or the product contract is explicitly narrowed.

## Test Setup

Required hardware/accounts:

- Device A: iPhone running the candidate build.
- Device B: separate iPhone running the candidate build.
- Wallet A: verified EVM or Solana account controlled on Device A.
- Wallet B: different verified EVM or Solana account controlled on Device B.
- Network controls: normal Wi-Fi/cellular, Airplane Mode, and a way to force app relaunch.

Record for every run:

- build number / git SHA
- iOS versions
- device models
- wallet apps/providers used
- WalletConnect project ID environment
- date/time
- tester names
- pass/fail notes and screenshots for failures

## Exit Rule

Ship decision is **go** only when:

- every Blocker is passed
- every Major is passed or explicitly accepted by product/security with mitigation
- every relay terms/quota item in `Social-v1-Relay-Readiness.md` is signed off
- every abuse/reliability item in `Social-v1-Abuse-and-Reliability.md` is signed off
- App Review copy avoids unsupported claims

## QA Matrix

| ID | Severity | Scenario | Required proof | Status |
| --- | --- | --- | --- | --- |
| SOC-Device-001 | Blocker | Device A creates a shared session invite. | Invite contains session ID, relay topic, expiry, and shareable QR/link; no plaintext wallet address/session metadata is visible in relay payload logs. | Not run |
| SOC-Device-002 | Blocker | Device B joins via invite and signs wallet challenge. | Both devices treat B as verified only after independently verifying the exact session-scoped signature; a local Boolean attestation is insufficient. | Blocked - portable peer proof not implemented |
| SOC-Device-003 | Blocker | Device B cancels wallet signature. | Join remains pending/unverified; B cannot vote or mutate queue. | Not run |
| SOC-Device-004 | Blocker | Device B signs with the wrong wallet account. | Join is rejected or remains unverified with clear error. | Not run |
| SOC-Device-005 | Blocker | Expired invite join attempt. | Join fails; no participant or relay subscription persists. | Not run |
| SOC-Device-006 | Blocker | Shared receipt/artifact/workflow from A appears on B. | B sees synced context once relay delivers events; duplicate delivery does not duplicate UI rows. | Not run |
| SOC-Device-007 | Blocker | Collaborative approval opens on A and B votes approve. | Approval resolves through existing governed approval path only after threshold; receipt records participant identity. | Blocked by SOC-Device-002 |
| SOC-Device-008 | Blocker | B rejects a collaborative approval. | Approval resolves rejected; proposed action does not execute; rejection receipt exists. | Blocked by SOC-Device-002 |
| SOC-Device-009 | Blocker | Collaborative queue proposal from B. | A sees proposal; accepted proposal mutates AuraPlay queue/playlist exactly once. | Blocked by SOC-Device-002 |
| SOC-Device-010 | Blocker | Queue reorder/remove under simultaneous edits. | Both devices converge to the same deterministic queue state after sync. | Blocked by SOC-Device-002 |
| SOC-Device-011 | Blocker | Collaborative ritual run. | Both devices show run state, outputs, receipts, and synced session context. | Not run |
| SOC-Device-012 | Blocker | Relay disconnect during pending event. | Event remains pending, UI shows degraded/offline state, event replays after reconnect. | Not run |
| SOC-Device-013 | Blocker | Relaunch both devices. | Sessions restore, relay subscriptions recover, missed messages fetch, and no duplicate queue/approval effects occur. | Not run |
| SOC-Device-014 | Blocker | Owner removes participant. | Removed participant can no longer cast binding votes or queue mutations after removal event syncs. | Not run |
| SOC-Device-015 | Blocker | Owner ends session. | Both devices show ended state; later mutating events are ignored. | Not run |
| SOC-Device-016 | Blocker | Privacy reset on Device A. | A clears sessions, invite keys, pending events, relay topics, rituals, and local queue collaboration state. | Not run |
| SOC-Device-017 | Major | Privacy reset on Device B while A remains active. | B leaves local state cleanly; A shows B absent/removed/pending according to implemented event policy. | Not run |
| SOC-Device-018 | Major | VoiceOver pass on session list/detail/invite/approval/queue/ritual screens. | Labels announce role, verification, vote state, sync state, and destructive actions clearly. | Not run |
| SOC-Device-019 | Major | Dynamic Type pass at largest accessibility sizes. | Invite, participant, queue, approval, and ritual controls remain usable without clipped critical text. | Not run |
| SOC-Device-020 | Major | Abuse handling: high-rate event attempts. | Local rate limit/throttle prevents UI or storage runaway and shows a clear degraded/error state. | Not run |

## Failure Reporting

Mirror every Blocker, Major, and accepted Minor into the relevant known-limitations or readiness doc:

- `Social-v1-Relay-Readiness.md` for relay terms/quota/reliability blockers
- `Social-v1-Abuse-and-Reliability.md` for safety or local moderation blockers, and for residual
  product risk against the implemented controls
- `Phase-1-Known-Limitations.md` only if the finding also affects the existing Phase 1 Mission Control surface

## Final Sign-Off

| Date | Build | Tester | Result | Notes |
| --- | --- | --- | --- | --- |
| _(not run)_ | | | | |
