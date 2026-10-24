# Social v1 - Abuse Handling and Reliability

**Status:** Most local controls are implemented. Production readiness remains blocked by relay evidence, physical QA,
and the missing portable wallet proof needed for one installation to verify another participant.
**Created:** 2026-08-21.
**Last reconciled with code:** 2026-10-22.
**Release rule:** App-only relay social can ship publicly only if these local controls are implemented, tested, and disclosed honestly.

The relay path is currently enabled in both Debug and Release. That configuration does not imply these release gates
have passed.

## Threat Model

Social v1 is invite-only and app-only. There is no Auralis-owned backend, central account system, global moderation queue, or server-side abuse investigation tool in v1.

That makes local and session-scoped controls mandatory:

- only people with an invite can reach a session topic
- only participants verified by the receiving installation can cast binding votes or mutate shared state
- owners can remove participants and end sessions
- every mutating event is authored, timestamped, deduped, and receipted when it affects governed app behavior
- privacy reset clears local social state

## Abuse Controls

| Risk | Required control | Release status |
| --- | --- | --- |
| Invite forwarding | Short invite expiry, random topic/key material, owner-visible participant join event. | Implemented (`SocialInviteMint`: random 256-bit topic + generated session key + nonce + expiry) |
| Impersonation | Wallet-signed join challenge tied to session, topic, CAIP-10 account, nonce, and expiry. | Local challenge and ownership verification implemented. The connector returns only a Boolean and discards the signature, so proof cannot yet travel to or be independently verified by a peer. Remote participants remain `.pending` and fail closed. |
| Vote stuffing | One active vote per verified participant per approval/proposal; role must allow voting. | Implemented and tested |
| Spam events | Per-session local event-rate limits, payload size caps, and UI throttling for repeated failures. | Implemented (payload cap + per-topic sliding-window inbound rate limit in `SocialRelayCoordinator`, fails closed to degraded) |
| Malformed payloads | Decode failure quarantine; no crash; no state mutation; optional diagnostic receipt. | Implemented (fail-closed decode + `SocialRelayDiagnostics` quarantine seam; inbound pump swallows per-message errors) |
| Wrong-key traffic | Drop/quarantine without showing plaintext error content. | Implemented (wrong-key decrypt fails to generic `.malformedPayload`; no plaintext surfaced; quarantine diagnostic) |
| Hostile participant | Owner can remove participant; removed participant events after removal are ignored. | Implemented (owner-only `participantRemoved`; post-removal binding events rejected by projection; tested) |
| Session takeover | Only owner can end session or change owner-level controls. Owner changes require explicit governed event. | Implemented (owner-only `sessionEnded`/`participantRemoved` gate in `SocialSessionProjection`; tested) |
| Unsafe approvals | Social votes never bypass `CryptoMode`, policy checks, proposal simulation, or approval receipts. | Governed resolution is implemented. Cross-device binding votes remain blocked until portable peer proof is implemented. |
| Local data residue | Privacy reset clears social sessions, relay topics, invite keys, pending events, and ritual state. | Implemented for local UserDefaults social payloads |

## Reliability Contract

The user-visible contract is local-first sync, not guaranteed live presence.

Required states:

- `Connected`: relay socket active and subscribed to session topic.
- `Syncing`: reconnecting, fetching missed messages, or replaying outbound events.
- `Offline`: no relay connection; local edits can queue if the session allows it.
- `Degraded`: relay connected but fetch/replay failed for at least one topic.
- `Blocked`: session key missing, invite expired, participant unverified, or owner ended session.

Required behavior:

- local events are append-only and durable until sent or privacy reset
- inbound events are idempotent
- accepted queue mutations apply exactly once
- collaborative approvals resolve exactly once
- relay outage never grants extra authority
- reconnect replay cannot resurrect an ended session

## Disclosure Notes

Public copy must avoid claims that imply centralized safety or moderation.

Allowed:

- "Invite-only shared sessions"
- "Wallet-verified participants"
- "Encrypted collaboration over relay transport"
- "Local-first sync with offline pending changes"

Not allowed for v1:

- "Public social network"
- "Moderated community platform"
- "Guaranteed real-time sync"
- "Live synchronized listening room"
- "Auralis can recover or moderate every shared session"

## Reliability Test Matrix

| Scenario | Expected result | Status |
| --- | --- | --- |
| Relay offline before join | Join blocks with retryable error; no verified participant is created. | Implemented with runtime/invite rollback; live device validation pending |
| Relay drops after local event | Event remains pending and visible; replay attempts after reconnect. | Local outbox implemented; live reconnect not run |
| Duplicate inbound event | State applies once. | Implemented and tested |
| Out-of-order events | Deterministic merge produces same final state on both devices. | Implemented and tested locally |
| Ended session receives new mutation | Mutation ignored and optionally logged as rejected. | Implemented with classified, privacy-safe diagnostic receipt |
| Privacy reset during pending sync | Local social state, keys, and pending outbound events are removed. | Implemented for local payloads |
| Remote participant proof | A peer independently verifies the exact wallet signature before accepting binding events. | Not implemented; local Boolean ownership results are not portable, so the receiving installation retains the participant as `.pending` and rejects binding events |

## Open Limitations

- No global account bans or device bans in app-only v1.
- No server-side takedown or audit retrieval after local data is reset.
- No guaranteed message delivery beyond relay availability and TTL.
- No conflict resolution based on server time; deterministic local merge is authoritative.
- Wallet verification is currently local to the joining installation. Until the exact signed message and EIP-191
  signature travel with `participantJoined` and are verified inbound, a remote peer cannot grant that participant
  binding authority. This is fail-closed, but it prevents the advertised cross-device approval and queue flows.
- Relay terms, quotas, acceptable-use, privacy metadata, retention, SLA, and production scaling remain unsigned in
  `Social-v1-Relay-Readiness.md` even though the relay flag is currently enabled for Debug and Release.
