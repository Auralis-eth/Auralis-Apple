import Foundation
import SocialCore
import WalletConnectorKit

protocol SocialEnvelopeCiphering: Sendable {
    func seal(_ envelope: SocialEventEnvelope) throws -> String
    func open(_ message: String) throws -> SocialEventEnvelope
}

protocol SocialRelayTransporting: Sendable {
    func subscribe(topic: String) async throws
    func publish(topic: String, message: String, tag: Int, ttl: Int) async throws
}

enum SocialRelayCoordinatorError: Error, Equatable, Sendable {
    case disabled
    case missingInvite(sessionID: UUID)
    case malformedPayload
    case oversizedPayload(limitBytes: Int)
    case rateLimited(topic: String)
}

/// Why an inbound relay payload was dropped without being applied. Surfaced through the coordinator's
/// diagnostics seam so the app can (optionally) emit a diagnostic receipt — never carrying plaintext.
enum SocialRelayQuarantineReason: String, Equatable, Sendable {
    case malformed
    case oversized
    case rateLimited
    /// The payload decrypted, but it named a session this coordinator is not bound to — or it
    /// arrived on a topic that is not this session's.
    ///
    /// A coordinator holds exactly one session key, and ``SocialEnvelopeCipher/open(_:)`` carries no
    /// session discriminator, so "it decrypted" only proves the sender holds *this* session's
    /// invite. Without this check an invite holder for session A could set `sessionID: B` and have
    /// the envelope appended to session B's graph — one invite reaching every session on the device.
    case foreignSession
}

/// Sink for quarantined-inbound diagnostics. Deliberately receives only the reason and the (opaque)
/// relay topic — never the payload — so a diagnostic receipt can never leak social plaintext.
protocol SocialRelayDiagnostics: Sendable {
    func recordQuarantine(reason: SocialRelayQuarantineReason, topic: String) async
    func recordRejectedEvent(
        reason: SocialSessionProjection.RejectionReason,
        sessionID: UUID,
        eventID: UUID
    ) async
    /// A locally-authored event that can never be published (over the sealed-payload ceiling) and has
    /// been dropped from the outbox.
    ///
    /// Distinct from ``recordQuarantine(reason:topic:)`` because this one is *the user's own* content
    /// being lost, so it must carry the session and event id — without them the drop is unattributable
    /// and the user has no way to know which share vanished.
    func recordDroppedOutbound(
        reason: SocialRelayQuarantineReason,
        sessionID: UUID,
        eventID: UUID
    ) async
    func recordOperationalEvent(_ event: SocialRelayOperationalEvent) async
}

extension SocialRelayDiagnostics {
    func recordRejectedEvent(
        reason: SocialSessionProjection.RejectionReason,
        sessionID: UUID,
        eventID: UUID
    ) async { }
    func recordDroppedOutbound(
        reason: SocialRelayQuarantineReason,
        sessionID: UUID,
        eventID: UUID
    ) async { }
    func recordOperationalEvent(_ event: SocialRelayOperationalEvent) async { }
}

enum SocialRelayOperationalEvent: Equatable, Sendable {
    case subscribeSucceeded
    case subscribeFailed
    case publishSucceeded
    case publishFailed
    case inboundAccepted
    case prune(SocialPruneResult)
}

/// Default no-op diagnostics: fail-closed drops still happen; nothing is recorded.
struct NoopSocialRelayDiagnostics: SocialRelayDiagnostics {
    func recordQuarantine(reason: SocialRelayQuarantineReason, topic: String) async { }
}

struct WalletConnectSocialRelayTransport: SocialRelayTransporting {
    private let relayClient: WalletConnectIRNRelayClient

    init(relayClient: WalletConnectIRNRelayClient) {
        self.relayClient = relayClient
    }

    func subscribe(topic: String) async throws {
        try await relayClient.subscribe(topic: topic)
    }

    func publish(topic: String, message: String, tag: Int, ttl: Int) async throws {
        try await relayClient.publish(
            WalletConnectRelayPublish(
                topic: topic,
                message: message,
                tag: tag,
                ttl: ttl,
                prompt: false
            )
        )
    }
}

/// Relay I/O for **one** shared session.
///
/// The single-session scope is not a simplification, it is the correctness boundary: this type holds
/// exactly one `cipher`, and `seal`/`open` carry no session discriminator. Before that scope was
/// enforced the type was wired to serve every session on the device — `subscribeToSavedInvites`
/// subscribed to *all* saved invite topics and `publishPendingOutbound` drained *all* pending
/// envelopes — which produced two distinct defects from one cause:
///
/// - **Outbound:** every session's backlog was sealed with this coordinator's key, so with two live
///   sessions, session B's envelopes went out on B's topic encrypted under A's key — undecryptable
///   by B's members — and `markPublished` cleared them regardless, losing them permanently.
/// - **Inbound:** `handleInbound` never related `envelope.sessionID` to `topic`, so any payload that
///   decrypted under this key was appended to whatever session it named. One invite reached every
///   session on the device.
///
/// Multi-session fan-out belongs to the layer that owns the *keys* — see ``SocialRelayComposition``,
/// which builds one runtime per invite.
actor SocialRelayCoordinator {
    private let configuration: SocialFeatureConfiguration
    private let eventLogStore: SocialEventLogStore
    private let transport: any SocialRelayTransporting
    private let cipher: any SocialEnvelopeCiphering
    /// The one session this coordinator's `cipher` can speak for.
    private let boundSessionID: UUID
    /// The one relay topic this coordinator subscribes to and publishes on.
    private let boundTopic: String
    private let maxPayloadBytes: Int
    private let relayTag: Int
    private let ttlSeconds: Int
    private let maxInboundPerWindow: Int
    private let inboundWindow: TimeInterval
    private let now: @Sendable () -> Date
    private let diagnostics: any SocialRelayDiagnostics
    /// Recent inbound arrival times on `boundTopic`, pruned to `inboundWindow`. Spam-control state
    /// (SOC-Device-020).
    private var inboundTimestamps: [Date] = []
    /// When the last durable diagnostic of each kind was written, so inbound traffic cannot amplify
    /// into the receipt ledger. Keyed by ``DiagnosticKind``, whose cases are fixed and few, so this
    /// dictionary is bounded by the enum rather than by anything a peer controls.
    private var lastDiagnosticAt: [DiagnosticKind: Date] = [:]
    /// Whether this session's `.degraded` state was set by the inbound limiter, so the next accepted
    /// message can clear it rather than leaving the session degraded until relaunch.
    private var isRateLimitDegraded = false

    init(
        configuration: SocialFeatureConfiguration,
        eventLogStore: SocialEventLogStore,
        transport: any SocialRelayTransporting,
        cipher: any SocialEnvelopeCiphering,
        boundSessionID: UUID,
        boundTopic: String,
        maxPayloadBytes: Int = 16 * 1024,
        relayTag: Int = 4_210,
        ttlSeconds: Int = 300,
        maxInboundPerWindow: Int = 240,
        inboundWindow: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init,
        diagnostics: any SocialRelayDiagnostics = NoopSocialRelayDiagnostics()
    ) {
        self.configuration = configuration
        self.eventLogStore = eventLogStore
        self.transport = transport
        self.cipher = cipher
        self.boundSessionID = boundSessionID
        self.boundTopic = boundTopic
        self.maxPayloadBytes = max(1, maxPayloadBytes)
        self.relayTag = relayTag
        self.ttlSeconds = max(1, ttlSeconds)
        self.maxInboundPerWindow = max(1, maxInboundPerWindow)
        self.inboundWindow = max(1, inboundWindow)
        self.now = now
        self.diagnostics = diagnostics
    }

    func subscribeToSavedInvites() async throws {
        try ensureEnabled()
        let pruneResult = await eventLogStore.prune(now: now())
        if pruneResult.removedEnvelopeCount > 0 || pruneResult.removedInviteCount > 0 {
            await diagnostics.recordOperationalEvent(.prune(pruneResult))
        }
        await setSyncState(.connecting)
        do {
            // This session's topic only. Subscribing to every saved invite pointed one coordinator —
            // which holds one key — at traffic it could not decrypt and had no business reading; it
            // is also what made the missing inbound session check reach the whole device. One
            // runtime per invite is built by `SocialRelayComposition`, each with its own key.
            //
            // An expired invite still subscribes nothing: the guard below keeps a lapsed session
            // from reconnecting, matching the pre-existing `where !invite.isExpired()` filter.
            guard let invite = await eventLogStore.allInvites()
                .first(where: { $0.sessionID == boundSessionID && !$0.isExpired(now: now()) }) else {
                await setSyncState(.degraded("No live invite for this session"))
                return
            }
            // Subscribe on `boundTopic`, not the stored invite's topic. The cipher and the inbound
            // `topic == boundTopic` check are both fixed at construction, so resolving the topic from
            // mutable storage here let a re-minted invite point this coordinator at a new topic while it
            // still held the old key — publishing undecryptable traffic and quarantining its own inbound
            // as a foreign session. The stored invite is still consulted, but only for liveness.
            guard invite.relayTopic == boundTopic else {
                await setSyncState(.degraded("Stored invite no longer matches this session's relay topic"))
                return
            }
            try await transport.subscribe(topic: boundTopic)
            await setSyncState(.connected)
            await diagnostics.recordOperationalEvent(.subscribeSucceeded)
        } catch {
            await setSyncState(.degraded(error.localizedDescription))
            await diagnostics.recordOperationalEvent(.subscribeFailed)
            throw error
        }
    }

    func publishPendingOutbound() async throws {
        try ensureEnabled()
        // Only this session's backlog. Draining every session's pending envelopes through this
        // coordinator sealed them all with *this* session's key: another session's envelope was
        // published on its own correct topic but encrypted under the wrong key, so no member of that
        // session could open it — and `markPublished` below cleared it anyway, so it was gone for
        // good. The envelopes left here stay pending for the coordinator that actually holds their key.
        guard let invite = await eventLogStore.allInvites().first(where: { $0.sessionID == boundSessionID }) else {
            throw SocialRelayCoordinatorError.missingInvite(sessionID: boundSessionID)
        }
        // `boundTopic` for the same reason as `subscribeToSavedInvites`: the key this envelope is sealed
        // with is the construction-time one, so it must go to the construction-time topic. A stored
        // invite that has drifted means the session needs rebuilding, not re-routing.
        guard invite.relayTopic == boundTopic else {
            throw SocialRelayCoordinatorError.missingInvite(sessionID: boundSessionID)
        }
        let topic = boundTopic
        for envelope in await eventLogStore.pendingOutbound() where envelope.sessionID == boundSessionID {
            let sealed = try cipher.seal(envelope)
            // An over-limit envelope is *permanently* un-publishable — retrying cannot shrink it —
            // so throwing here head-of-line-blocked the session's entire outbox forever, and every
            // later envelope was punished for one oversized predecessor. Worse, `joinSession`
            // catches a throw out of `runtime.start()` and **deletes the invite**, destroying the
            // relay topic and session key over a payload-size problem, forcing a rescan.
            //
            // `SocialQueueSnapshot` has no item cap and `SharedAgentContext` permits 2,000
            // characters plus 32 class names and 100 artifact ids against a 16 KiB sealed ceiling,
            // so this is reachable from ordinary use rather than only from an attack.
            //
            // Dropped from the queue and recorded instead: the drain continues, and the diagnostics
            // seam carries the fact rather than the payload.
            guard sealed.utf8.count <= maxPayloadBytes else {
                await eventLogStore.markPublished(eventID: envelope.id)
                // Attributed to the session and event, not just the topic: this is the user's own
                // content being discarded, and an unattributable record leaves them unable to tell
                // which share was lost or to re-author it.
                await diagnostics.recordDroppedOutbound(
                    reason: .oversized,
                    sessionID: envelope.sessionID,
                    eventID: envelope.id
                )
                continue
            }
            do {
                try await transport.publish(topic: topic, message: sealed, tag: relayTag, ttl: ttlSeconds)
                await eventLogStore.markPublished(eventID: envelope.id)
                await diagnostics.recordOperationalEvent(.publishSucceeded)
            } catch {
                await diagnostics.recordOperationalEvent(.publishFailed)
                throw error
            }
        }
    }

    func handleInbound(message: String, topic: String) async throws {
        try ensureEnabled()
        // Foreign-topic traffic is discarded *first*, before it can touch any of this session's state.
        // When the limiter ran first, a flood on another session's topic both marked **this** session
        // `.degraded` in Mission Control and grew a per-topic bucket that was never pruned — the exact
        // cross-session bleed this type was scoped to eliminate. One coordinator serves one topic, so
        // anything else is not ours to account for.
        //
        // Nothing is recorded, deliberately. ``SocialRelayInboundBroadcaster`` fans every inbound relay
        // message to every live session's pump, so with two sessions a topic mismatch is the *expected*
        // case for roughly half of all traffic, not an anomaly. `recordQuarantine` appends a signed,
        // sequenced receipt, so recording here turned ordinary two-session operation into one extra
        // durable receipt per message — unbounded growth driven by normal use, and the amplification the
        // rate-limit throttle below exists to prevent.
        guard topic == boundTopic else { return }
        // Count every arrival (good or bad) so a flood of malformed/oversized junk still trips the
        // limit. Rate-limited, oversized, wrong-key, and malformed payloads all fail closed: the pump
        // swallows the throw, no plaintext is surfaced, and the diagnostics seam is notified.
        guard admitInbound() else {
            // Deliberately *not* a per-message quarantine record. `recordQuarantine` appends a signed,
            // sequenced receipt to the durable ledger, so recording one per refused message let a peer
            // holding the topic convert a bounded CPU cost into unbounded durable growth — the limiter
            // would bound the work and not the storage. One record per window carries the same fact.
            // Only the durable receipt is throttled; the *state* is set on every refusal. With the
            // degrade inside the throttle, a flood that tripped the limit, paused long enough for one
            // envelope to be accepted (clearing the flag and setting `.connected`), then resumed inside
            // the same window would leave Mission Control reporting a healthy session while every
            // message was being refused — the throttle is a storage bound, not a state machine.
            await setSyncState(.degraded("Inbound rate limit exceeded"))
            isRateLimitDegraded = true
            if admitDiagnostic(.quarantine(.rateLimited)) {
                await diagnostics.recordQuarantine(reason: .rateLimited, topic: topic)
            }
            throw SocialRelayCoordinatorError.rateLimited(topic: topic)
        }
        guard message.utf8.count <= maxPayloadBytes else {
            if admitDiagnostic(.quarantine(.oversized)) {
                await diagnostics.recordQuarantine(reason: .oversized, topic: topic)
            }
            throw SocialRelayCoordinatorError.oversizedPayload(limitBytes: maxPayloadBytes)
        }
        do {
            let envelope = try cipher.open(message)
            // Decrypting proves the sender holds *this* session's invite — nothing more. `open`
            // carries no session discriminator, so without this the payload's own `sessionID` chose
            // which graph it was appended to, and an invite holder for one session could write into
            // every other session on the device. Checked before `rejectionReason`, because the
            // projection it would consult is the wrong session's.
            guard envelope.sessionID == boundSessionID else {
                if admitDiagnostic(.quarantine(.foreignSession)) {
                    await diagnostics.recordQuarantine(reason: .foreignSession, topic: topic)
                }
                return
            }
            let projection = await eventLogStore.projection(sessionID: envelope.sessionID)
            if let reason = projection.rejectionReason(for: envelope) {
                if admitDiagnostic(.rejectedEvent(reason)) {
                    await diagnostics.recordRejectedEvent(
                        reason: reason,
                        sessionID: envelope.sessionID,
                        eventID: envelope.id
                    )
                }
                return
            }
            await eventLogStore.appendInbound(envelope, topic: topic)
            await diagnostics.recordOperationalEvent(.inboundAccepted)
            // Recover from a rate-limit degrade. `.connected` was only ever set by
            // `subscribeToSavedInvites`, which does not re-run on a live session, so one flood left
            // Mission Control reporting the session degraded until the app was relaunched and rejoined
            // — long after the traffic returned to normal. An accepted message is proof it has.
            if isRateLimitDegraded {
                isRateLimitDegraded = false
                await setSyncState(.connected)
            }
        } catch {
            if admitDiagnostic(.quarantine(.malformed)) {
                await diagnostics.recordQuarantine(reason: .malformed, topic: topic)
            }
            throw SocialRelayCoordinatorError.malformedPayload
        }
    }

    /// Sliding-window admission for inbound relay traffic on this coordinator's bound topic. Returns
    /// `false` (and records nothing new) once `maxInboundPerWindow` arrivals land within `inboundWindow`.
    ///
    /// A single bucket, not a dictionary: callers reach here only after the `topic == boundTopic` guard,
    /// so there is exactly one topic to account for. The old per-topic dictionary also retained an entry
    /// for every topic ever seen, which a peer could grow without bound.
    private func admitInbound() -> Bool {
        let cutoff = now().addingTimeInterval(-inboundWindow)
        inboundTimestamps = inboundTimestamps.filter { $0 > cutoff }
        guard inboundTimestamps.count < maxInboundPerWindow else { return false }
        inboundTimestamps.append(now())
        return true
    }

    /// The kinds of durable diagnostic this coordinator can emit for inbound traffic, each throttled
    /// independently so one noisy failure mode cannot mask another.
    private enum DiagnosticKind: Hashable {
        case quarantine(SocialRelayQuarantineReason)
        /// Keyed by the rejection reason, not collapsed into one bucket.
        ///
        /// Collapsing them let ordinary traffic bury the security-relevant cases. `.unverifiedAuthor`
        /// is the *normal* state for a member whose optional wallet proof did not complete, so their
        /// every queue mutation is rejected — a benign, high-rate stream that would consume the single
        /// slot in each window and leave an `impersonatedAuthor` or `mismatchedAccount` rejection in
        /// the same window with no durable record at all. The reason set is fixed and small, so keying
        /// by it preserves the bound while keeping each signal reportable.
        case rejectedEvent(SocialSessionProjection.RejectionReason)
    }

    /// Admits at most one durable diagnostic of `kind` per `inboundWindow`, so inbound traffic produces
    /// a bounded number of receipts instead of one per message.
    ///
    /// This throttle used to apply to the rate-limited branch alone, which left the amplification it
    /// exists to prevent wide open on every other path: `.oversized`, `.malformed`, `.foreignSession`,
    /// and `recordRejectedEvent` each appended one signed, sequenced receipt per *admitted* arrival.
    /// A session member or the relay operator — anyone who can see the topic — could publish junk just
    /// under the rate limit, have every message fail `cipher.open`, and turn a bounded CPU cost into
    /// hundreds of thousands of permanent ledger rows a day. The limiter bounded the work; nothing
    /// bounded the storage. One record per kind per window carries the same operational fact.
    private func admitDiagnostic(_ kind: DiagnosticKind) -> Bool {
        let moment = now()
        if let last = lastDiagnosticAt[kind], moment.timeIntervalSince(last) < inboundWindow {
            return false
        }
        lastDiagnosticAt[kind] = moment
        return true
    }

    private func ensureEnabled() throws {
        guard configuration.relayEnabled else {
            throw SocialRelayCoordinatorError.disabled
        }
    }

    /// This session's sync state, and only this session's.
    ///
    /// Missed when the rest of the type was scoped, and it is the one place the old all-sessions
    /// wiring survived: it wrote every saved invite's state. With one runtime per invite that means
    /// each coordinator overwrites the others — session B's socket failure marked session A
    /// `.degraded` with B's error string, and an inbound flood on *any* topic marked every session
    /// on the device degraded. Mission Control reads `syncStates[session.id]`, so the user saw a
    /// healthy session reporting another one's failure.
    private func setSyncState(_ state: SocialSyncState) async {
        await eventLogStore.setSyncState(state, for: boundSessionID)
    }
}

private extension SocialSyncState {
    static var connecting: SocialSyncState {
        SocialSyncState(phase: .connecting)
    }

    static var connected: SocialSyncState {
        SocialSyncState(phase: .connected)
    }

    static func degraded(_ message: String) -> SocialSyncState {
        SocialSyncState(phase: .degraded, lastErrorSummary: message)
    }
}
