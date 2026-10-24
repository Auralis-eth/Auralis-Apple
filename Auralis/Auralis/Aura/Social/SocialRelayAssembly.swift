import Foundation
import SocialCore
import WalletConnectorKit

/// The transport + inbound source a session needs. Abstracted so production wires the live
/// WalletConnect/IRN relay while tests inject fakes.
struct SocialRelayCollaborators: Sendable {
    let transport: any SocialRelayTransporting
    let inboundSource: any SocialRelayInboundStreaming
}

/// App-level composition root that hosts and joins Social v1 shared sessions over the relay.
///
/// Owns the started per-session runtimes (so their inbound pumps stay alive) and reuses the app's single
/// durable ``SocialEventLogStore`` (from `RuntimeHost`), so relay state and Mission Control's projected
/// state read the same log. Everything is gated: when `AURALIS_SOCIAL_RELAY_ENABLED` is off,
/// `hostSession` returns `nil`, `joinSession` returns `false`, and no socket is opened. **The flag ships
/// on** — see ``SocialAssembly`` — so these paths are live in production.
///
/// Builds the live AuraPlay playlist target a session's collaborative queue reconciles into, or `nil`
/// when no playlist can be bound (e.g. AuraPlay storage unavailable). One factory per assembly; it is
/// only consulted when relay social is enabled.
typealias SocialQueuePlaylistTargetFactory = @Sendable (SocialInvite) async -> (any SocialQueuePlaylistTarget)?

actor SocialRelayAssembly {
    private let composition: SocialRelayComposition
    private let collaboratorsFactory: @Sendable (SocialInvite) -> SocialRelayCollaborators
    /// Optional collaborative-queue → AuraPlay wiring (P4). When present, each started session gets a
    /// ``SocialQueueCoordinator`` that reconciles a linked playlist to the session's accepted queue on
    /// every inbound relay message. `nil` (the default, and always when relay social is off) leaves the
    /// queue path inert.
    private let queuePlaylistTargetFactory: SocialQueuePlaylistTargetFactory?
    private var runtimes: [UUID: SocialRelaySessionRuntime] = [:]
    private var queueCoordinators: [UUID: SocialQueueCoordinator] = [:]
    /// Invites whose runtime is being built right now, keyed by session.
    ///
    /// Holds the *invite*, not just the id, so a second scan arriving mid-flight can be judged
    /// synchronously: an identical invite is a duplicate scan, a differing one is a conflict. Deciding
    /// that from the store instead would require an `await`, and the in-flight call may not have
    /// persisted yet — so the read would be stale exactly when it matters.
    private var startingInvites: [UUID: SocialInvite] = [:]

    init(
        composition: SocialRelayComposition,
        collaboratorsFactory: @escaping @Sendable (SocialInvite) -> SocialRelayCollaborators,
        queuePlaylistTargetFactory: SocialQueuePlaylistTargetFactory? = nil
    ) {
        self.composition = composition
        self.collaboratorsFactory = collaboratorsFactory
        self.queuePlaylistTargetFactory = queuePlaylistTargetFactory
    }

    /// Production wiring over one shared relay client (topics differ per session, so one client serves
    /// all sessions). Reuses the runtime's durable event-log store. Inert until the relay flag is on.
    static func live(
        configuration: SocialFeatureConfiguration,
        eventLogStore: SocialEventLogStore,
        relayClient: WalletConnectIRNRelayClient,
        diagnostics: any SocialRelayDiagnostics = NoopSocialRelayDiagnostics(),
        queuePlaylistTargetFactory: SocialQueuePlaylistTargetFactory? = nil
    ) -> SocialRelayAssembly {
        // One broadcaster for the whole assembly. The relay client's event stream is unicast, so each
        // session must read from its own fan-out branch rather than competing for the socket directly.
        let broadcaster = SocialRelayInboundBroadcaster(relayClient: relayClient)
        return SocialRelayAssembly(
            composition: SocialRelayComposition(
                configuration: configuration,
                eventLogStore: eventLogStore,
                diagnostics: diagnostics
            ),
            collaboratorsFactory: { _ in
                SocialRelayCollaborators(
                    transport: WalletConnectSocialRelayTransport(relayClient: relayClient),
                    inboundSource: WalletConnectSocialRelayInboundSource(broadcaster: broadcaster)
                )
            },
            queuePlaylistTargetFactory: queuePlaylistTargetFactory
        )
    }

    var isEnabled: Bool { composition.isEnabled }

    /// Mints an invite for a new shared session, persists it, and starts its relay runtime. Returns the
    /// invite to hand out (QR/share sheet), or `nil` when relay social is disabled.
    func hostSession(
        sessionID: UUID,
        inviterParticipantID: String,
        now: Date = .now,
        ttl: TimeInterval = SocialInviteMint.defaultTTL
    ) async throws -> SocialInvite? {
        guard composition.isEnabled else { return nil }

        // Re-hosting a session that already has a live runtime must not mint over it. Minting produces a
        // fresh relay topic *and* a fresh session key, but the running coordinator captured the previous
        // key at construction — so a second mint left the device publishing to the new topic sealed with
        // the old key (unreadable by anyone holding either QR) while quarantining every inbound message
        // on the new topic as a foreign session. The session was silently bricked and the UI said
        // "invite generated". Hand back the live invite instead; it is still the one that works.
        // A *running* session hands back its live invite. A session merely being started by a concurrent
        // call does not: that call's invite is saved before its runtime exists, so returning it here
        // would advertise a QR for a session that may still fail to start — and whose rollback then
        // deletes the very invite this caller was handed. Double-tapping "Generate invite" must not
        // produce a code for a session with no runtime behind it.
        if runtimes[sessionID] != nil {
            if let existing = await composition.eventLogStore.allInvites()
                .first(where: { $0.sessionID == sessionID && !$0.isExpired(now: now) }) {
                return existing
            }
            throw SocialJoinError.sessionAlreadyActive
        }
        guard startingInvites[sessionID] == nil else {
            throw SocialJoinError.sessionAlreadyActive
        }

        // Reserved here, before the first suspension, not inside `startRuntime`. Reserving only there
        // left a window: this method suspends on `saveInvite` before the reservation lands, so a second
        // concurrent host for the same session passed the guard above, minted a *second* invite over the
        // stored one, then hit `startRuntime`'s early return and handed its unstarted invite to the UI.
        let invite = SocialInviteMint.mint(
            sessionID: sessionID,
            inviterParticipantID: inviterParticipantID,
            now: now,
            ttl: ttl
        )
        startingInvites[sessionID] = invite
        defer { startingInvites[sessionID] = nil }

        await composition.eventLogStore.saveInvite(invite)
        do {
            try await startRuntime(for: invite)
        } catch {
            // Same atomicity contract as `joinSession`: a host that could not start leaves no invite
            // behind advertising a topic nothing is listening on.
            await stopSession(sessionID: sessionID)
            await composition.eventLogStore.removeInvite(sessionID: sessionID)
            throw error
        }
        return invite
    }

    /// Joins a shared session from a received invite: persists it and starts its relay runtime. Returns
    /// `false` when relay social is disabled.
    @discardableResult
    func joinSession(invite: SocialInvite) async throws -> Bool {
        guard composition.isEnabled else { return false }
        guard !invite.isExpired() else { throw SocialJoinError.expiredInvite }

        // A join for this session is already in flight. Judge the invite against the in-flight one
        // *before* short-circuiting: returning `true` for any invite naming a busy session would report
        // "Joined" for an attacker's conflicting code — the same wrong answer the stored-invite guard
        // below exists to prevent, just one step earlier. Compared synchronously against the in-flight
        // invite rather than the store, because the other call may not have persisted yet.
        if let inFlight = startingInvites[invite.sessionID] {
            guard inFlight.relayTopic == invite.relayTopic,
                  inFlight.inviterParticipantID == invite.inviterParticipantID,
                  inFlight.encryptedSessionKey == invite.encryptedSessionKey else {
                throw SocialJoinError.conflictingInvite
            }
            return true
        }
        // Reserved before the first suspension — see `hostSession`. The conflict check below reads the
        // store, so without this a second scan could pass it on stale state.
        startingInvites[invite.sessionID] = invite
        defer { startingInvites[invite.sessionID] = nil }

        // An invite that reuses a session id this device already holds is refused unless it is the same
        // invite. `saveInvite` replaces the stored invite for its session id *and* durably adds the
        // inviter to that session's owner-bootstrap anchor set — so without this guard, anyone who
        // photographed a QR for session S (or merely belongs to it) could mint their own invite with the
        // same session id and get the victim to scan it, rewriting the stored relay topic and session key
        // and installing themselves as an owner anchor for a session they never hosted.
        let alreadyStored = await composition.eventLogStore.allInvites()
            .first(where: { $0.sessionID == invite.sessionID })
        if let alreadyStored {
            guard alreadyStored.relayTopic == invite.relayTopic,
                  alreadyStored.inviterParticipantID == invite.inviterParticipantID,
                  alreadyStored.encryptedSessionKey == invite.encryptedSessionKey else {
                throw SocialJoinError.conflictingInvite
            }
            // Only *after* the conflict check, which is a security boundary: short-circuiting on
            // "already running" first would hand an attacker's conflicting invite a `true` return for
            // any session currently live, which is exactly the overwrite this guard exists to refuse.
            // Reaching here means the invite is byte-identical to the stored one, so a re-scan of a
            // live session is a genuine no-op.
            if runtimes[invite.sessionID] != nil { return true }
        }

        await composition.eventLogStore.saveInvite(invite)
        do {
            try await startRuntime(for: invite)
            return true
        } catch {
            // Rollback is deliberate and stays: a join that could not start leaves no half-joined
            // state behind — no saved invite for a session this device never entered, and no
            // runtime to keep retrying it. Pinned by `relayFailureRollsBackJoin`.
            //
            // This was briefly narrowed to spare the invite on transport failures, on the theory
            // that a dropped socket should not cost the user a rescan. That reasoning applied to a
            // trigger that no longer exists: the case worth worrying about was an oversized payload
            // aborting the drain, and `publishPendingOutbound` now drops and records such an
            // envelope rather than throwing. What remains are genuine "could not join" failures,
            // where atomicity is the better contract.
            await stopSession(sessionID: invite.sessionID)
            // ...but only for an invite this call actually introduced. Nothing restarts runtimes at
            // launch, so re-scanning a QR for a session joined in an earlier launch reaches here with
            // the invite already durably held; deleting it on an offline retry would destroy that
            // session's relay topic and session key, which `hostSession` cannot re-mint. Atomicity
            // means "leave no state this call created", not "delete state it found".
            if alreadyStored == nil {
                await composition.eventLogStore.removeInvite(sessionID: invite.sessionID)
            }
            throw error
        }
    }

    /// Joins from an encoded invite string (scanned or pasted). Throws ``SocialInviteCodingError`` for a
    /// malformed code before touching the relay.
    @discardableResult
    func joinSession(code: String) async throws -> Bool {
        try await joinSession(invite: SocialInviteCoding.decode(code))
    }

    /// Stops and forgets a session's runtime (its inbound pump is torn down) and its queue coordinator.
    func stopSession(sessionID: UUID) async {
        if let coordinator = queueCoordinators.removeValue(forKey: sessionID) { await coordinator.stop() }
        guard let runtime = runtimes.removeValue(forKey: sessionID) else { return }
        await runtime.stop()
    }

    /// Session IDs with a live runtime — for status surfaces and tests.
    func activeSessionIDs() -> [UUID] { Array(runtimes.keys) }

    /// Builds and starts one session's runtime.
    ///
    /// - Precondition: the caller already holds this session's `startingInvites` reservation.
    ///   ``hostSession(sessionID:inviterParticipantID:now:ttl:)`` and ``joinSession(invite:)`` take it
    ///   before their first suspension, which is what makes the guard below sufficient: this actor is
    ///   reentrant, and the guard and the `runtimes[...] = runtime` write are separated by two awaits.
    ///   Without the caller's reservation, two concurrent joins each built a pump and the loser's was
    ///   never recorded — so `stopSession` could not cancel it and it drained the inbound stream forever.
    private func startRuntime(for invite: SocialInvite) async throws {
        guard runtimes[invite.sessionID] == nil else { return }

        let collaborators = collaboratorsFactory(invite)
        // P4: bind a collaborative-queue coordinator (if a playlist target is available) and reconcile
        // the linked playlist on every inbound relay message. No target ⇒ no coordinator ⇒ inert hook.
        let queueCoordinator = await makeQueueCoordinator(for: invite)
        let onInboundProcessed: @Sendable () async -> Void
        if let queueCoordinator {
            onInboundProcessed = { _ = try? await queueCoordinator.reconcile() }
        } else {
            onInboundProcessed = { }
        }
        guard let runtime = try composition.makeSession(
            for: invite,
            transport: collaborators.transport,
            inboundSource: collaborators.inboundSource,
            onInboundProcessed: onInboundProcessed
        ) else { return }
        runtimes[invite.sessionID] = runtime
        if let queueCoordinator { queueCoordinators[invite.sessionID] = queueCoordinator }
        do {
            try await runtime.start()
        } catch {
            await runtime.stop()
            runtimes.removeValue(forKey: invite.sessionID)
            if let coordinator = queueCoordinators.removeValue(forKey: invite.sessionID) {
                await coordinator.stop()
            }
            throw error
        }
        // Reconcile once now so any queue events replayed from the relay mailbox on subscribe (or already
        // in the durable log) land in the playlist without waiting for the next live message.
        if let queueCoordinator { _ = try? await queueCoordinator.reconcile() }
    }

    private func makeQueueCoordinator(for invite: SocialInvite) async -> SocialQueueCoordinator? {
        guard let queuePlaylistTargetFactory, let target = await queuePlaylistTargetFactory(invite) else {
            return nil
        }
        return SocialQueueCoordinator(
            eventLogStore: composition.eventLogStore,
            sessionID: invite.sessionID,
            playlistTarget: target
        )
    }
}

enum SocialJoinError: LocalizedError, Equatable {
    case expiredInvite
    /// A different invite claims a session id this device already holds — see ``SocialRelayAssembly``.
    case conflictingInvite
    /// A host was requested for a session that is already running and has no usable stored invite.
    case sessionAlreadyActive

    var errorDescription: String? {
        switch self {
        case .expiredInvite:
            return "This shared-session invite has expired. Ask the host for a new invite."
        case .conflictingInvite:
            return "This invite claims a shared session you've already joined, but its relay details "
                + "don't match. Ask the host to re-share the original invite."
        case .sessionAlreadyActive:
            return "This shared session is already running on this device."
        }
    }
}
