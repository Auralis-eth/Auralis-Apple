# Social v1 - WalletConnect/IRN Relay Readiness

**Status:** Relay implementation is live in Debug and Release; production-readiness evidence remains blocked.
**Created:** 2026-08-21.
**Last reconciled with code:** 2026-10-22.
**Release rule:** Social v1 cannot be production-public until every `Required evidence` item below is filled in with source links, dates, and an owner sign-off.

**Current configuration warning:** `AURALIS_SOCIAL_RELAY_ENABLED` is `YES` in both
`Auralis-Debug.xcconfig` and `Auralis-Release.xcconfig`. That does not satisfy or waive this release rule. Until the
evidence and physical-device gates close, enabling the production path is an explicitly unresolved release risk.

## Intended Relay Usage

Social v1 plans to use the existing WalletConnect/IRN relay capability as an app-only encrypted message transport for invite-only collaboration sessions.

| Area | Planned behavior | Release status |
| --- | --- | --- |
| Relay topics | One opaque random topic per shared session, distributed only through the session invite. | Code seam implemented; live usage blocked |
| Payload content | Encrypted JSON `SocialEventEnvelope`; relay sees ciphertext only. | Production AES-GCM `SocialEnvelopeCipher` implemented and tested locally; live transport inspection pending |
| Payload metadata | Topic, tag, TTL, and ciphertext length only; no wallet address/session title/playlist name in topic or plaintext. | Code seam implemented; terms review blocked |
| Message flow | Subscribe, fetch missed messages, publish encrypted events, dedupe on receipt. | Subscribe/publish/outbox/dedupe and paged missed-message fetch implemented; physical reconnect/replay QA pending |
| Offline behavior | Local pending queue, visible degraded state, replay on reconnect. | Local queue and sync state implemented; live reconnect QA blocked |
| Data retention | Local event retention cleared by privacy reset; relay retention depends on WalletConnect/IRN TTL behavior. | Local reset implemented; relay retention blocked pending terms review |

## Required Evidence

| Gate | Evidence needed | Owner | Status |
| --- | --- | --- | --- |
| Terms of service | Confirm WalletConnect/IRN terms allow app-specific encrypted collaboration payloads, not only wallet protocol traffic. Link exact terms reviewed. | TBD | Blocked |
| Quotas/rate limits | Document project-level message, topic, connection, fetch, TTL, and payload-size limits. Include source or support response. | TBD | Blocked |
| Acceptable use | Confirm invite-only social collaboration is permitted and does not violate relay anti-abuse policy. | TBD | Blocked |
| Privacy posture | Document what relay can observe: topic, timing, IP/socket metadata, ciphertext length, TTL/tag. Confirm no plaintext social data leaves device. | TBD | Blocked |
| Retention | Document relay queued-message TTL, fetch behavior, and whether deleted/expired messages can be recovered. | TBD | Blocked |
| Reliability/SLA | Document expected availability, reconnect assumptions, and what the app shows during relay outage. | TBD | Blocked |
| Production scaling | Estimate session message volume and compare with confirmed quotas. | TBD | Blocked |

## Planned Wire Contract

The app-side social relay adapter publishes only encrypted envelopes.

```text
relay topic: random 32-byte topic encoded as lowercase hex or base64url
relay tag: social event tag assigned by implementation
relay ttl: short queueing TTL chosen after quota/terms review
relay message: encrypted SocialEventEnvelope
```

The plaintext envelope before encryption contains:

- protocol version
- event ID
- session ID
- author participant ID
- author CAIP-10 account
- created timestamp
- optional parent/latest-known event IDs
- event payload
- signature/proof reference

The encrypted payload must not exceed the documented relay payload limit. Oversized events must fail before publish and present a user-visible error.

## Reliability Requirements

The relay adapter must support:

- connect coalescing
- reconnect with capped backoff and jitter
- fetch missed messages before subscribing after reconnect
- outbound pending event replay
- inbound dedupe by event ID
- wrong-key/malformed payload quarantine
- visible sync state in Mission Control
- privacy reset teardown of topics, pending events, session keys, and local event logs

Code status:

- `SocialEventLogStore` persists event envelopes, pending outbound IDs, invites, replay cursors, and sync state.
- `UserDefaultsSocialEventLogPersistence` stores the local event/outbox payload and privacy reset removes it.
- `SocialRelayCoordinator` subscribes saved invites, seals outbound envelopes with the production AES-GCM cipher,
  enforces payload and inbound-rate limits, publishes through `WalletConnectIRNRelayClient`, clears published outbox
  entries, and quarantines malformed or wrong-key inbound payloads.
- `WalletConnectIRNRelayClient` performs paged missed-message fetch before subscription and repeats recovery during
  resubscription. Its real relay behavior remains unverified by the two-device suite.
- `SocialRelayAssembly` hosts one runtime per session and fans the relay client's inbound stream out to those runtimes.
- The path remains gated by `AURALIS_SOCIAL_RELAY_ENABLED`, but the current Debug and Release defaults are both `YES`.
- Cross-device participant authority is not complete: the wallet connector ownership seam returns a local Boolean and
  does not carry a portable signature/proof to peers. Remote installations therefore keep that participant `.pending`
  and reject their binding votes and queue mutations. This is tracked in `P0-Future-Work.md`.

## Release Decision Log

| Date | Decision | Evidence | Owner |
| --- | --- | --- | --- |
| 2026-08-21 | Initial status: blocked until WalletConnect/IRN terms, quota, retention, and reliability evidence are gathered. | This document. | TBD |
| 2026-08-21 | Non-device relay code seam may merge behind `AURALIS_SOCIAL_RELAY_ENABLED = NO`; production-public relay remains blocked. | `SocialEventLogStore`, `UserDefaultsSocialEventLogPersistence`, `SocialRelayCoordinator`, SocialCore/RuntimeKit/app tests. | Engineering |
| 2026-08-27 | Current non-device release stance: code-level relay controls may remain merged, but `AURALIS_SOCIAL_RELAY_ENABLED = NO` in Debug + Release while every `Required evidence` row above is still Blocked. Terms/quota/retention/SLA were not obtained; relay behavior at production scale remains unproven and may be throttled or disallowed by WalletConnect/IRN. | Completion plan update; build settings restored to default-off. | Engineering |
| 2026-10-22 | Reconciled the document with the shipping configuration and implementation. Debug and Release now set the relay flag to `YES`; AES-GCM encryption and missed-message recovery are implemented. No terms, quota, retention, SLA, scaling, or physical-device evidence was found, and portable peer wallet proof remains unimplemented. The release gate is therefore still blocked despite the enabled configuration. | Current xcconfigs, Social relay implementation, `P0-Future-Work.md`, and physical QA suite. | Engineering; release-risk owner TBD |
