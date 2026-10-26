import CryptoKit
import Foundation
import Security

/// A functional WalletConnect v2 Sign transport over the IRN relay.
///
/// Implements the dapp side of the handshake: it creates a pairing, publishes a
/// `wc_sessionPropose`, derives the session key from the wallet's response,
/// processes `wc_sessionSettle`, and correlates `wc_sessionRequest` responses.
/// All relay traffic is ChaCha20-Poly1305 encrypted (see `WalletConnectV2Crypto`).
///
/// Session state is held in memory for the lifetime of the client; cross-launch
/// restoration is layered on top via the keychain session/topic stores.
public actor WalletConnectIRNTransportClient: WalletTransportClient {
    private struct PendingProposal {
        let pairing: WalletPairing
        let providerID: WalletProviderID
        // CAIP-2 chain identifiers (plus aliases) this proposal requested. Used to
        // reject a settle that grants accounts on chains we never asked for. Empty
        // means "no proposal constraint" (accept whatever settles).
        let allowedChains: Set<String>
        let requiredNamespaces: WalletNamespaceProposalSet
        var pairingTopic: String { pairing.topic.rawValue }
    }

    /// A proposal that has been answered (session key derived) but has not yet
    /// settled. Retained so the pairing-window timeout can still report an
    /// expiry, and so a failed session-topic subscribe can be surfaced.
    private struct ConnectingSession {
        let pairing: WalletPairing
        let providerID: WalletProviderID
        let sessionTopic: String
    }

    private struct SessionContext {
        let providerID: WalletProviderID
        let pairingTopic: String?
        // Carried from the proposal so settle/update can drop accounts on chains
        // that were never proposed. Restored sessions persist this constraint.
        var allowedChains: Set<String> = []
        // Required namespaces are a protocol boundary: settle/update must satisfy
        // every required chain/method/event/account before the session is live.
        var requiredNamespaces: WalletNamespaceProposalSet = .empty
    }

    private let relayClient: WalletConnectIRNRelayClient
    private let stateStore: any WalletConnectSessionStatePersisting
    private let now: @Sendable () -> Date
    private let eventsStream: AsyncStream<WalletTransportEvent>
    private let eventsContinuation: AsyncStream<WalletTransportEvent>.Continuation
    private let pendingRequests = WalletPendingRequestStore()
    // Bridges relay events onto this transport's event stream. Retained so it can
    // be cancelled in `deinit`; the loop holds the relay strongly and `self`
    // weakly, so without an explicit cancel the relay (and its live socket) would
    // leak because `relay.events` never finishes on its own. `nonisolated(unsafe)`
    // is sound here: it is assigned exactly once in `init` (before any
    // concurrency touches the actor) and read only in `deinit` (after the last
    // reference is gone).
    private nonisolated(unsafe) var eventBridgeTask: Task<Void, Never>?

    private var symKeyByTopic: [String: Data] = [:]
    private var selfKeyByTopic: [String: Curve25519.KeyAgreement.PrivateKey] = [:]
    private var pendingProposalByID: [Int64: PendingProposal] = [:]
    private var connectingByProposalID: [Int64: ConnectingSession] = [:]
    private var proposalIDBySessionTopic: [String: Int64] = [:]
    private var proposalTimeoutTasks: [Int64: Task<Void, Never>] = [:]
    private var contextByTopic: [String: SessionContext] = [:]
    private var sessionsByTopic: [String: WalletSession] = [:]
    // Binds an outbound `wc_sessionRequest` wire id to the session topic it was
    // published on, so a response is only accepted when it arrives on that same
    // topic (blocks cross-session response injection). Cleared when the request
    // resolves, times out, or is cancelled.
    private var requestTopicByWireID: [Int64: String] = [:]
    private var counter: Int64 = 0
    private var lastIssuedID: Int64 = 0
    // Coalesces first-use restoration into a single task. The actor is re-entrant
    // across `await`, so a bare `didRestore` bool set before the awaited
    // `loadAll()` let a second caller observe a half-restored (empty) state and,
    // e.g., throw `sessionExpired` for a session that IS persisted but not yet
    // rehydrated. Every caller now awaits this one task instead (same pattern the
    // relay client uses to coalesce concurrent `connect()`).
    private var restoreTask: Task<Void, Error>?

    // Dedup of inbound relay messages: the relay may redeliver the same encrypted
    // message (e.g. wc_sessionSettle / wc_sessionDelete), which would otherwise
    // re-emit sessionApproved / sessionDeleted. Eviction is time-based so a
    // long-lived signature (a delete can be redelivered anytime within its relay
    // TTL) is not evicted early by a burst of unrelated traffic; a generous hard
    // cap still bounds memory under flooding.
    private var seenMessageAt: [String: Date] = [:]
    private var seenMessageOrder: [String] = []
    // Must cover the longest relay message TTL (wc_sessionDelete: 86 400 s) so a
    // redelivered delete stays deduplicated for its whole lifetime.
    private let seenMessageTTL: TimeInterval = 86_400
    private let maxSeenMessages = 4_096
    // WalletConnect v2 caps a session's lifetime at 7 days. A peer sets the
    // settle `expiry`, so clamp it: an unbounded far-future expiry would keep the
    // persisted session key material and the subscribed topic alive indefinitely.
    private let maxSessionLifetime: TimeInterval = 604_800
    private let minimumRequestExpiryInterval: TimeInterval = 300
    private let maximumRequestExpiryInterval: TimeInterval = 604_800

    // Correlates our own outbound `wc_sessionPing` / `wc_sessionExtend` requests
    // with the wallet's ack (a bare `{id,result}` response). The wire id is
    // reserved in `outboundAckWireIDs` before publishing so an inbound ack routes
    // to the ack path even if it arrives before the waiter registers; such an
    // early ack is buffered in `bufferedAckByID` and consumed on registration.
    private var outboundAckWireIDs: Set<Int64> = []
    private var pendingAckByID: [Int64: CheckedContinuation<Void, Error>] = [:]
    private var bufferedAckByID: [Int64: Result<Void, Error>] = [:]
    private var ackTimeoutTasks: [Int64: Task<Void, Never>] = [:]

    // Keepalive/liveness. A periodic sweep pings each live session (so a dead peer
    // surfaces) and auto-extends a session that is within `autoExtendThreshold` of
    // its expiry, up to the 7-day protocol cap. `nil` interval disables the sweep.
    private let keepAliveInterval: Duration?
    private let pongTimeout: Duration
    private let autoExtendThreshold: TimeInterval
    // Topics whose last keepalive ping went unanswered, so the "dead peer"
    // diagnostic fires once per outage instead of every sweep.
    private var keepAliveUnresponsiveTopics: Set<String> = []
    // Assigned once in `init` (before concurrency touches the actor) and read only
    // in `deinit`; sound for the same reason as `eventBridgeTask`.
    private nonisolated(unsafe) var keepAliveTask: Task<Void, Never>?
    // Optional structured-log sink for otherwise-silent moments (restore summary,
    // a keepalive ping a peer never answered). Lets a host surface a dead peer or
    // a restore that recovered fewer sessions than expected.
    private let onDiagnostic: (@Sendable (String) -> Void)?

    public init(
        relayClient: WalletConnectIRNRelayClient,
        // Default to the shared keychain-backed store so a bare transport actually
        // survives relaunch. The in-memory store stays available as an explicit
        // opt-in for hermetic tests and callers that deliberately forgo restoration.
        stateStore: any WalletConnectSessionStatePersisting = KeychainWalletConnectSessionStateStore.shared,
        now: @escaping @Sendable () -> Date = Date.init,
        // Liveness sweep cadence. Defaults to 5 minutes; pass `nil` to disable
        // (tests, or hosts that drive keepalive themselves).
        keepAliveInterval: Duration? = .seconds(300),
        pongTimeout: Duration = .seconds(15),
        autoExtendThreshold: TimeInterval = 86_400,
        onDiagnostic: (@Sendable (String) -> Void)? = nil
    ) {
        self.relayClient = relayClient
        self.stateStore = stateStore
        self.now = now
        self.keepAliveInterval = keepAliveInterval
        self.pongTimeout = pongTimeout
        self.autoExtendThreshold = autoExtendThreshold
        self.onDiagnostic = onDiagnostic
        let stream = AsyncStream<WalletTransportEvent>.makeStream()
        self.eventsStream = stream.stream
        self.eventsContinuation = stream.continuation
        // Bridge relay events without pinning `self` alive for the loop's whole
        // life: hold the relay strongly (it is peer-lifetime), hop to a weak
        // `self` per event, and stop as soon as the transport is gone so the
        // actor can deallocate instead of leaking behind an endless loop.
        eventBridgeTask = Task { [weak self, relay = relayClient] in
            for await event in relay.events {
                guard let self else { break }
                await self.handle(relayEvent: event)
            }
            await self?.finishEvents()
        }
        if let keepAliveInterval {
            keepAliveTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: keepAliveInterval)
                    guard let self else { return }
                    await self.runKeepAlive()
                }
            }
        }
    }

    deinit {
        // Break the strong hold the bridge loop keeps on the relay so the relay
        // (and its WebSocket) can deallocate; `relay.events` never finishes by
        // itself, so cancelling the loop is what releases it.
        eventBridgeTask?.cancel()
        keepAliveTask?.cancel()
    }

    // MARK: - Cross-launch restoration

    /// Rehydrates persisted sessions on first use: restores each session's
    /// symmetric key, local key-agreement key, and metadata, re-subscribes to
    /// its topic so inbound requests/deletes are received, and prunes expired
    /// records. Idempotent and cheap after the first call.
    private func ensureRestored() async throws {
        // Join an in-flight restore rather than starting a second one, and never
        // return before the first restore actually finished populating state.
        if let restoreTask {
            try await restoreTask.value
            return
        }
        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.performRestore()
        }
        restoreTask = task
        do {
            try await task.value
        } catch {
            restoreTask = nil
            throw error
        }
    }

    private func performRestore() async throws {
        let persisted = try await stateStore.loadAll()
        var restoredSymKeys: [String: Data] = [:]
        var restoredSelfKeys: [String: Curve25519.KeyAgreement.PrivateKey] = [:]
        var restoredContexts: [String: SessionContext] = [:]
        var restoredSessions: [String: WalletSession] = [:]

        for session in persisted {
            guard session.expiryDate > now() else {
                try await stateStore.delete(sessionTopic: session.sessionTopic)
                continue
            }
            guard let symKey = WalletConnectV2Crypto.data(hexEncoded: session.sessionSymmetricKeyHex),
                  symKey.count == 32 else {
                throw WalletConnectionError.cryptographyFailure
            }
            restoredSymKeys[session.sessionTopic] = symKey
            if let hex = session.selfPrivateKeyHex {
                guard let keyData = WalletConnectV2Crypto.data(hexEncoded: hex),
                      let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: keyData) else {
                    throw WalletConnectionError.cryptographyFailure
                }
                restoredSelfKeys[session.sessionTopic] = key
            }
            restoredContexts[session.sessionTopic] = SessionContext(
                providerID: session.providerID,
                pairingTopic: session.pairingTopic,
                allowedChains: session.allowedChains ?? Self.allowedChainIdentifiers(from: session.accounts),
                requiredNamespaces: session.requiredNamespaces ?? .empty
            )
            restoredSessions[session.sessionTopic] = session.walletSession
        }

        // Rehydrate in-memory state BEFORE touching the network, so `sessions()`,
        // `disconnect()`, and metadata reads work even while the relay is
        // unreachable (offline launch). Coupling enumeration/teardown to a live
        // socket previously made a persisted session invisible and un-removable
        // when offline.
        symKeyByTopic.merge(restoredSymKeys) { _, restored in restored }
        selfKeyByTopic.merge(restoredSelfKeys) { _, restored in restored }
        contextByTopic.merge(restoredContexts) { _, restored in restored }
        sessionsByTopic.merge(restoredSessions) { _, restored in restored }

        // Re-subscribe best-effort so peer-initiated traffic (update/delete/event)
        // resumes, but never fail the restore on a socket error — the relay client
        // re-subscribes on its own reconnect, and `request()` ensures its topic is
        // subscribed on demand. Detached so an offline launch does not block on the
        // per-topic ack timeout.
        let topicsToSubscribe = Array(restoredSessions.keys)
        onDiagnostic?("WalletConnect restore: rehydrated \(restoredSessions.count) session(s); re-subscribing \(topicsToSubscribe.count) topic(s).")
        if !topicsToSubscribe.isEmpty {
            Task { [relay = relayClient, onDiagnostic] in
                for topic in topicsToSubscribe {
                    do {
                        try await relay.subscribe(topic: topic)
                    } catch {
                        // Never fail the restore on a subscribe error (the relay
                        // re-subscribes on its own reconnect, and `request()`
                        // subscribes on demand), but do not swallow it silently:
                        // a topic that could not be re-subscribed here — e.g. a
                        // very large queued mailbox that exceeds the fetch-page cap —
                        // will miss peer-initiated update/delete traffic until the
                        // next outbound call on it, so surface it as a diagnostic.
                        onDiagnostic?("WalletConnect restore: failed to re-subscribe topic \(topic) (\(error.localizedDescription)); peer-initiated update/delete may be missed until the next request on this topic.")
                    }
                }
            }
        }
    }

    public nonisolated func events() -> AsyncStream<WalletTransportEvent> {
        eventsStream
    }

    // MARK: - Pairing + proposal

    public func createPairing(request: WalletPairingRequest) async throws -> WalletPairing {
        try await ensureRestored()

        let symKey = try Self.randomBytes(32)
        let symKeyHex = WalletConnectV2Crypto.hexString(symKey)
        let pairingTopic = WalletConnectV2Crypto.topic(forSymmetricKey: symKey)
        let allowedChains = Self.allowedChainIdentifiers(request.requiredNamespaces, request.optionalNamespaces)
        symKeyByTopic[pairingTopic] = symKey
        contextByTopic[pairingTopic] = SessionContext(
            providerID: request.providerID,
            pairingTopic: pairingTopic,
            allowedChains: allowedChains,
            requiredNamespaces: request.requiredNamespaces
        )

        let expiryDate = now().addingTimeInterval(300)
        let uri = WalletConnectURI(
            topic: pairingTopic,
            symKey: symKeyHex,
            expiryTimestamp: Int64(expiryDate.timeIntervalSince1970),
            methods: ["wc_sessionPropose"]
        )

        try await relayClient.subscribe(topic: pairingTopic)

        // Generate the proposer key and publish wc_sessionPropose on the pairing
        // topic. The wallet opens the pairing URI, joins the topic, and responds.
        let selfKey = WalletConnectV2Crypto.generateKeyPair()
        selfKeyByTopic[pairingTopic] = selfKey.privateKey

        let proposal = WCSessionProposal(
            relays: [WCRelayProtocolOptions()],
            proposer: WCParticipant(publicKey: selfKey.publicKeyHex, metadata: WCAppMetadata(metadata: request.metadata)),
            requiredNamespaces: Self.proposalNamespaces(request.requiredNamespaces),
            optionalNamespaces: Self.proposalNamespaces(request.optionalNamespaces),
            expiryTimestamp: UInt64(expiryDate.timeIntervalSince1970)
        )

        let pairing = WalletPairing(
            topic: WalletPairingTopic(rawValue: pairingTopic),
            providerID: request.providerID,
            uri: uri.absoluteString,
            expiryDate: expiryDate
        )

        let requestID = nextID()
        pendingProposalByID[requestID] = PendingProposal(
            pairing: pairing,
            providerID: request.providerID,
            allowedChains: allowedChains,
            requiredNamespaces: request.requiredNamespaces
        )
        try await publishRequest(
            method: WalletConnectSignMethod.propose,
            params: proposal,
            id: requestID,
            tag: WalletConnectSignTag.sessionPropose,
            topic: pairingTopic,
            symKey: symKey
        )
        // Arm a single window that spans propose → settle. If the wallet never
        // responds, or responds but never settles, the pairing expires with a
        // reported event instead of hanging forever.
        scheduleProposalTimeout(id: requestID, pairing: pairing)

        eventsContinuation.yield(.pairingCreated(pairing))
        return pairing
    }

    // MARK: - Requests

    public func request(_ request: WalletRequest, topic: WalletPairingTopic) async throws -> WalletResponse {
        try await ensureRestored()
        let sessionTopic = topic.rawValue
        // Drop a session that has passed its expiry before using it, so a caller
        // (and any UI derived from it) never rides a dead session in a long-running
        // process where expiry was only enforced at restore/settle time.
        if let session = sessionsByTopic[sessionTopic], session.expiryDate <= now() {
            try await pruneSession(topic: sessionTopic)
            throw WalletConnectionError.sessionExpired
        }
        guard let session = sessionsByTopic[sessionTopic], let symKey = symKeyByTopic[sessionTopic] else {
            throw WalletConnectionError.sessionExpired
        }
        try WalletRequestValidation.validate(request)
        try WalletSessionGrantValidator.validate(request, in: session)

        // Restore now subscribes best-effort/detached, so guarantee this topic is
        // subscribed before publishing — otherwise the wallet's response could
        // arrive on a topic we are not listening on. Idempotent on a live socket.
        try await relayClient.subscribe(topic: sessionTopic)

        let wireID = nextID()
        let wireRequestID = WalletSignRequestID(rawValue: String(wireID))
        // Record which session topic this request rides on so only a response
        // delivered on that same topic can resolve it. Cleared on any exit.
        requestTopicByWireID[wireID] = sessionTopic
        defer { requestTopicByWireID.removeValue(forKey: wireID) }
        let params = WCRequestParams(
            request: WCRequestParams.Request(
                method: request.method.rawValue,
                params: .array(request.params),
                expiryTimestamp: UInt64(request.expiryDate.timeIntervalSince1970)
            ),
            chainId: request.chain.caip2
        )

        try await publishRequest(
            method: WalletConnectSignMethod.request,
            params: params,
            id: wireID,
            tag: WalletConnectSignTag.sessionRequest,
            topic: sessionTopic,
            symKey: symKey,
            ttl: relayTTL(forRequestExpiringAt: request.expiryDate)
        )

        let response = try await pendingRequests.wait(id: wireRequestID, expiryDate: request.expiryDate)
        // Hand the caller a response tagged with the id they supplied.
        return WalletResponse(id: request.id, result: response.result)
    }

    // MARK: - Disconnect

    public func disconnect(topic: WalletPairingTopic) async throws {
        try await ensureRestored()
        let sessionTopic = topic.rawValue
        let symKey = symKeyByTopic[sessionTopic]
        // Durable delete first, but non-fatally: a keychain that is momentarily
        // unreadable (device locked, missing entitlement) must not block the user's
        // local disconnect. Surface the failure as an event and still tear down
        // locally below so in-memory state never diverges from the user's intent.
        do {
            try await stateStore.delete(sessionTopic: sessionTopic)
        } catch {
            yieldPersistenceDeleteFailure(topic: sessionTopic, error: error)
        }

        // Tear down local state synchronously so `disconnect` returns promptly and
        // the UI reflects it immediately — even offline.
        cleanupTopicState(sessionTopic)
        // Fail any in-flight request on this topic now instead of letting it hang
        // until its own expiry — the session it was riding is gone.
        failPendingRequests(forTopic: sessionTopic, error: .sessionExpired)

        // Network side effects are best-effort and MUST NOT block the caller: a
        // dead/unreachable relay would otherwise stall disconnect on the publish
        // and unsubscribe ack timeouts (~15s each). Fire them off the caller's
        // path. The remote `wc_sessionDelete` id is minted here (on the actor).
        //
        // Seal the delete envelope now, on the actor, and hand the detached task
        // only the finished message plus the (strongly-held) relay. Previously the
        // task captured `self` weakly and built the envelope via `self?.publishRequest`,
        // so a transport deallocated in the same turn as `disconnect()` — the common
        // "remove wallet, tear down connector" flow — skipped the publish entirely
        // and left the wallet showing a stale live session. The message no longer
        // depends on `self`, so the peer is notified even if the transport is gone.
        let deleteID = nextID()
        let deleteTag = WalletConnectSignTag.sessionDelete
        let sealedDelete = symKey.flatMap { key in
            try? Self.sealedType0Message(
                method: WalletConnectSignMethod.delete,
                params: WCReason.userDisconnected,
                id: deleteID,
                symKey: key
            )
        }
        Task { [relay = relayClient, sealedDelete, sessionTopic, deleteTag] in
            if let sealedDelete {
                try? await relay.publish(
                    WalletConnectRelayPublish(
                        topic: sessionTopic,
                        message: sealedDelete,
                        tag: deleteTag,
                        ttl: WalletConnectSignTag.ttl(for: deleteTag)
                    )
                )
            }
            await relay.unsubscribe(topic: sessionTopic)
        }
    }

    public func sessions() async throws -> [WalletSession] {
        try await ensureRestored()
        try await pruneExpiredSessions()
        return Array(sessionsByTopic.values)
    }

    /// Flags the live session on `topic` as ownership-verified and re-persists it,
    /// so `sessions()` (and a cross-launch restore) reports `addressVerified`.
    public func markOwnershipVerified(topic: WalletPairingTopic) async throws {
        try await ensureRestored()
        let sessionTopic = topic.rawValue
        guard let session = sessionsByTopic[sessionTopic], !session.addressVerified else { return }
        let verified = WalletSession(
            id: session.id,
            topic: session.topic,
            providerID: session.providerID,
            providerName: session.providerName,
            accounts: session.accounts,
            namespaces: session.namespaces,
            connectedAt: session.connectedAt,
            expiryDate: session.expiryDate,
            addressVerified: true
        )
        guard let symKey = symKeyByTopic[sessionTopic] else {
            throw WalletConnectionError.sessionExpired
        }
        try await persist(session: verified, symKey: symKey, pairingTopic: contextByTopic[sessionTopic]?.pairingTopic ?? sessionTopic)
        sessionsByTopic[sessionTopic] = verified
    }

    // MARK: - Keepalive & expiry extension

    /// Sends a `wc_sessionPing` and awaits the wallet's pong, throwing if the peer
    /// does not respond within `pongTimeout`. Lets a host detect a dead peer on a
    /// session that still looks live locally.
    public func ping(topic: WalletPairingTopic) async throws {
        try await ensureRestored()
        let sessionTopic = topic.rawValue
        guard sessionsByTopic[sessionTopic] != nil, let symKey = symKeyByTopic[sessionTopic] else {
            throw WalletConnectionError.sessionExpired
        }
        try await relayClient.subscribe(topic: sessionTopic)
        let wireID = nextID()
        try await publishAwaitingAck(
            method: WalletConnectSignMethod.ping,
            params: WalletConnectEmptyResult(),
            wireID: wireID,
            tag: WalletConnectSignTag.sessionPing,
            topic: sessionTopic,
            symKey: symKey
        )
    }

    /// Extends the session's expiry via `wc_sessionExtend`, clamped to the 7-day
    /// protocol cap. Awaits the wallet's ack, then adopts the new expiry locally
    /// and re-persists. A target not later than the current expiry is a no-op.
    @discardableResult
    public func extend(topic: WalletPairingTopic, to newExpiry: Date) async throws -> Bool {
        try await ensureRestored()
        let sessionTopic = topic.rawValue
        guard let existing = sessionsByTopic[sessionTopic], let symKey = symKeyByTopic[sessionTopic] else {
            throw WalletConnectionError.sessionExpired
        }
        let clamped = min(newExpiry, now().addingTimeInterval(maxSessionLifetime))
        guard clamped > existing.expiryDate else { return false }

        try await relayClient.subscribe(topic: sessionTopic)
        let wireID = nextID()
        try await publishAwaitingAck(
            method: WalletConnectSignMethod.extend,
            params: WCExtendParams(expiry: Int64(clamped.timeIntervalSince1970)),
            wireID: wireID,
            tag: WalletConnectSignTag.sessionExtend,
            topic: sessionTopic,
            symKey: symKey
        )

        // The peer acked; adopt the new expiry. Re-read the session in case it
        // changed while we awaited the ack.
        guard let current = sessionsByTopic[sessionTopic] else { throw WalletConnectionError.sessionExpired }
        let extended = WalletSession(
            id: current.id,
            topic: current.topic,
            providerID: current.providerID,
            providerName: current.providerName,
            accounts: current.accounts,
            namespaces: current.namespaces,
            connectedAt: current.connectedAt,
            expiryDate: clamped,
            addressVerified: current.addressVerified
        )
        try await persist(session: extended, symKey: symKey, pairingTopic: contextByTopic[sessionTopic]?.pairingTopic ?? sessionTopic)
        sessionsByTopic[sessionTopic] = extended
        eventsContinuation.yield(.sessionUpdated(extended))
        return true
    }

    /// Periodic liveness sweep: auto-extends a session nearing expiry and pings
    /// each live session so a dead peer surfaces. Best-effort — a failure on one
    /// session never aborts the sweep or tears a session down (a missed pong can
    /// be transient).
    ///
    /// Sessions are swept **concurrently** so the total cost is bounded by a single
    /// `pongTimeout` regardless of how many sessions are live — a wallet that never
    /// pongs (or does not implement dapp-initiated ping/extend) cannot make the
    /// sweep cost `N × pongTimeout`.
    private func runKeepAlive() async {
        let sessions = Array(sessionsByTopic.values)
        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask { [weak self] in
                    await self?.keepAlive(session: session)
                }
            }
        }
    }

    private func keepAlive(session: WalletSession) async {
        if session.expiryDate.timeIntervalSince(now()) < autoExtendThreshold {
            _ = try? await extend(topic: session.topic, to: now().addingTimeInterval(maxSessionLifetime))
        }
        // A live session may have been torn down while we awaited the extend.
        guard sessionsByTopic[session.topic.rawValue] != nil else { return }
        do {
            try await ping(topic: session.topic)
            keepAliveUnresponsiveTopics.remove(session.topic.rawValue)
        } catch {
            // Surface a newly-unresponsive peer once (not every sweep) so a host
            // can react without log spam. Best-effort — a missed pong can be
            // transient, so we do not tear the session down.
            if keepAliveUnresponsiveTopics.insert(session.topic.rawValue).inserted {
                onDiagnostic?("WalletConnect keepalive: session \(session.topic.rawValue) did not respond to ping (\(error.localizedDescription)).")
            }
        }
    }

    /// Reserves `wireID` for the ack path, publishes the request, then awaits the
    /// peer's ack. Reserving before publishing means an ack that beats the waiter
    /// is still routed here (and buffered), closing the race that otherwise dropped
    /// a fast pong and hung to the timeout.
    private func publishAwaitingAck(
        method: String,
        params: some Encodable,
        wireID: Int64,
        tag: Int,
        topic: String,
        symKey: Data
    ) async throws {
        outboundAckWireIDs.insert(wireID)
        do {
            try await publishRequest(method: method, params: params, id: wireID, tag: tag, topic: topic, symKey: symKey)
        } catch {
            outboundAckWireIDs.remove(wireID)
            bufferedAckByID.removeValue(forKey: wireID)
            throw error
        }
        try await awaitPeerAck(wireID: wireID)
    }

    private func awaitPeerAck(wireID: Int64) async throws {
        // An ack that arrived before we registered was buffered — consume it.
        if let buffered = bufferedAckByID.removeValue(forKey: wireID) {
            outboundAckWireIDs.remove(wireID)
            try buffered.get()
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingAckByID[wireID] = continuation
            ackTimeoutTasks[wireID] = Task { [weak self, pongTimeout] in
                try? await Task.sleep(for: pongTimeout)
                await self?.timeoutPeerAck(wireID)
            }
        }
    }

    private func handlePeerAckResponse(id: Int64, rpc: WalletConnectRPCEnvelope) {
        ackTimeoutTasks.removeValue(forKey: id)?.cancel()
        let outcome: Result<Void, Error> = rpc.error
            .map { .failure(Self.mapError(code: $0.code, message: $0.message)) } ?? .success(())
        if let continuation = pendingAckByID.removeValue(forKey: id) {
            outboundAckWireIDs.remove(id)
            continuation.resume(with: outcome)
        } else {
            // Ack beat the waiter; buffer it for `awaitPeerAck` to consume.
            bufferedAckByID[id] = outcome
        }
    }

    private func timeoutPeerAck(_ id: Int64) {
        ackTimeoutTasks.removeValue(forKey: id)
        outboundAckWireIDs.remove(id)
        pendingAckByID.removeValue(forKey: id)?.resume(
            throwing: WalletConnectionError.relayAcknowledgementFailed("Peer did not acknowledge session ping/extend in time.")
        )
    }

    // MARK: - Inbound relay pipeline

    private func handle(relayEvent event: WalletConnectRelayEvent) async {
        switch event {
        case .socketStatusChanged(let status):
            eventsContinuation.yield(.socketStatusChanged(status))
        case .subscription(let topic, let message, _):
            await handleInbound(topic: topic, message: message)
        }
    }

    private func finishEvents() {
        eventsContinuation.finish()
    }

    private func handleInbound(topic: String, message: String) async {
        guard let envelope = try? WalletConnectEnvelope(base64Encoded: message) else { return }

        let symKey: Data
        let type1SenderPublicKey: Data?
        switch envelope.type {
        case .type0:
            guard let key = symKeyByTopic[topic] else { return }
            symKey = key
            type1SenderPublicKey = nil
        case .type1(let senderPublicKey):
            // A type1 (key-carrying) envelope is only legitimate as the wallet's
            // wc_sessionPropose response, and only on a pairing topic that still
            // has a live pending proposal. Reject it on an established session
            // topic and on any topic without a pending proposal, so authenticity
            // never depends on topic secrecy: a leaked session topic must not let
            // a peer seal a fresh key and have us process a forged peer request.
            guard sessionsByTopic[topic] == nil,
                  pendingProposalByID.values.contains(where: { $0.pairingTopic == topic }),
                  let selfKey = selfKeyByTopic[topic],
                  let derived = try? WalletConnectV2Crypto.deriveSymmetricKey(
                      privateKey: selfKey,
                      peerPublicKeyHex: WalletConnectV2Crypto.hexString(senderPublicKey)
                  ) else { return }
            symKey = derived
            type1SenderPublicKey = senderPublicKey
        }

        guard let plaintext = try? WalletConnectV2Crypto.open(sealbox: envelope.sealbox, symKey: symKey),
              let rpc = try? WalletConnectJSONCoding.decoder.decode(WalletConnectRPCEnvelope.self, from: plaintext) else {
            return
        }

        // Dedup on the decrypted identity, not the ciphertext: relay redelivery
        // (identical bytes) and a peer legitimately re-sending the same logical
        // message with a fresh nonce (different bytes) must both be suppressed so
        // settle/delete events fire exactly once.
        guard registerInboundMessage(dedupKey(topic: topic, rpc: rpc)) else {
            // The side effects already ran on first delivery, but the peer may
            // not have seen our ack and is retrying. Re-send the idempotent ack
            // for request types that expect one (settle/ping/event) so the wallet
            // stops retrying — without re-emitting sessionApproved/Deleted.
            if type1SenderPublicKey == nil, let method = rpc.method, let id = rpc.id {
                reackDuplicatePeerRequest(method: method, id: id, topic: topic, symKey: symKey)
            }
            return
        }

        // A type1 envelope routes exclusively to the propose-response path: it must
        // carry no peer method and its id must match a pending proposal. Anything
        // else on a type1 envelope is rejected outright.
        if let senderPublicKey = type1SenderPublicKey {
            guard rpc.method == nil, let id = rpc.id, pendingProposalByID[id] != nil else { return }
            handleProposeResponse(id: id, senderPublicKey: senderPublicKey, rpc: rpc)
            return
        }

        if let method = rpc.method {
            await handlePeerRequest(method: method, topic: topic, symKey: symKey, rpc: rpc)
        } else if let id = rpc.id {
            if pendingProposalByID[id] != nil {
                handleProposeResponse(id: id, senderPublicKey: nil, rpc: rpc)
            } else if outboundAckWireIDs.contains(id) {
                // The wallet's ack for our own ping/extend. Routed ahead of the
                // request-response path (whose topic binding it would otherwise
                // fail, silently dropping the pong). The id is reserved before we
                // publish, so this fires even if the ack beats the waiter.
                handlePeerAckResponse(id: id, rpc: rpc)
            } else {
                handleRequestResponse(id: id, topic: topic, rpc: rpc)
            }
        }
    }

    /// A stable identity for an inbound RPC used for duplicate suppression:
    /// peer requests key on `(topic, method, id)`, responses on `(topic, id)`.
    private func dedupKey(topic: String, rpc: WalletConnectRPCEnvelope) -> String {
        let id = rpc.id.map(String.init) ?? "nil"
        if let method = rpc.method {
            return "\(topic)|req|\(method)|\(id)"
        }
        return "\(topic)|resp|\(id)"
    }

    /// Re-sends the idempotent acknowledgement for a redelivered peer request
    /// whose side effects already ran. Settle/update/extend/ping/event carry an
    /// ack the wallet waits on; a redelivered delete never reaches here (its
    /// symKey is already torn down), and re-acking must not mutate state or emit
    /// events (the dedup gate already ran the first-delivery side effects once).
    private func reackDuplicatePeerRequest(method: String, id: Int64, topic: String, symKey: Data) {
        let tag: Int
        switch method {
        case WalletConnectSignMethod.settle:
            tag = WalletConnectSignTag.sessionSettleResponse
        case WalletConnectSignMethod.update:
            tag = WalletConnectSignTag.sessionUpdateResponse
        case WalletConnectSignMethod.extend:
            tag = WalletConnectSignTag.sessionExtendResponse
        case WalletConnectSignMethod.ping:
            tag = WalletConnectSignTag.sessionPingResponse
        case WalletConnectSignMethod.event:
            tag = WalletConnectSignTag.sessionEventResponse
        default:
            return
        }
        ackPeerRequest(id: id, topic: topic, symKey: symKey, tag: tag)
    }

    private func handlePeerRequest(method: String, topic: String, symKey: Data, rpc: WalletConnectRPCEnvelope) async {
        guard let id = rpc.id else { return }
        switch method {
        case WalletConnectSignMethod.settle:
            await handleSettle(topic: topic, id: id, symKey: symKey, params: rpc.params)
        case WalletConnectSignMethod.delete:
            // Only a live session is deletable by the peer. A delete that decrypts
            // on a topic with NO live session — most importantly a lingering pairing
            // topic, whose symKey is a bearer secret exchanged out-of-band via the
            // URI — must not tear down state or emit a spurious `.sessionDeleted`
            // (whose id would not even be a session topic). Ack it idempotently so
            // the peer stops retrying, then return without side effects. Every other
            // peer-request case is already guarded on a live session; delete was the
            // sole exception.
            guard sessionsByTopic[topic] != nil else {
                ackPeerRequest(id: id, topic: topic, symKey: symKey, tag: WalletConnectSignTag.sessionDeleteResponse)
                return
            }
            // The peer tore the session down. Attempt the durable delete, but if it
            // fails surface it and still ack + clean up locally — bailing here would
            // leave a session the wallet already killed alive locally and the wallet
            // retrying the delete forever.
            do {
                try await stateStore.delete(sessionTopic: topic)
            } catch {
                yieldPersistenceDeleteFailure(topic: topic, error: error)
            }
            ackPeerRequest(id: id, topic: topic, symKey: symKey, tag: WalletConnectSignTag.sessionDeleteResponse)
            cleanupTopicState(topic)
            // The peer tore the session down; fail any request still awaiting a
            // response on it rather than leaving the caller hanging until expiry.
            failPendingRequests(forTopic: topic, error: .sessionExpired)
            await relayClient.unsubscribe(topic: topic)
            eventsContinuation.yield(.sessionDeleted(WalletSessionID(rawValue: topic)))
        case WalletConnectSignMethod.update:
            await handleUpdate(topic: topic, id: id, symKey: symKey, params: rpc.params)
        case WalletConnectSignMethod.extend:
            await handleExtend(topic: topic, id: id, symKey: symKey, params: rpc.params)
        case WalletConnectSignMethod.ping:
            ackPeerRequest(id: id, topic: topic, symKey: symKey, tag: WalletConnectSignTag.sessionPingResponse)
        case WalletConnectSignMethod.event:
            handleEvent(topic: topic, id: id, symKey: symKey, params: rpc.params)
        default:
            break
        }
    }

    /// Applies a wallet-initiated `wc_sessionUpdate`: replaces the live session's
    /// namespaces/accounts (re-scoped to the chains we proposed, exactly as at
    /// settle), re-persists, acks, and emits `.sessionUpdated`. Only a live
    /// session is updatable; an update on an unknown topic is ignored. If the
    /// account set actually changes, `addressVerified` is reset to `false` —
    /// prior ownership proof covered the old accounts, not the new ones.
    private func handleUpdate(topic: String, id: Int64, symKey: Data, params: WalletJSONValue?) async {
        guard let existing = sessionsByTopic[topic] else { return }
        guard let params, let update = try? params.decoded(as: WCUpdateParams.self) else { return }

        let (accounts, namespaces) = Self.scopedAccountsAndNamespaces(
            update.namespaces,
            allowedChains: contextByTopic[topic]?.allowedChains ?? []
        )
        guard !accounts.isEmpty, namespaces.contains(where: { !$0.accounts.isEmpty }) else {
            await deleteAfterInvalidUpdate(topic: topic, id: id, symKey: symKey)
            return
        }
        do {
            try Self.validateRequiredNamespaces(
                contextByTopic[topic]?.requiredNamespaces ?? .empty,
                against: namespaces
            )
        } catch {
            await deleteAfterInvalidUpdate(topic: topic, id: id, symKey: symKey)
            return
        }
        let accountsChanged = accounts != existing.accounts
        let updated = WalletSession(
            id: existing.id,
            topic: existing.topic,
            providerID: existing.providerID,
            providerName: existing.providerName,
            accounts: accounts,
            namespaces: namespaces,
            connectedAt: existing.connectedAt,
            expiryDate: existing.expiryDate,
            addressVerified: existing.addressVerified && !accountsChanged
        )
        do {
            try await persist(session: updated, symKey: symKey, pairingTopic: contextByTopic[topic]?.pairingTopic ?? topic)
        } catch {
            return
        }
        sessionsByTopic[topic] = updated
        ackPeerRequest(id: id, topic: topic, symKey: symKey, tag: WalletConnectSignTag.sessionUpdateResponse)
        eventsContinuation.yield(.sessionUpdated(updated))
    }

    private func deleteAfterInvalidUpdate(topic: String, id: Int64, symKey: Data) async {
        do {
            try await stateStore.delete(sessionTopic: topic)
        } catch {
            yieldPersistenceDeleteFailure(topic: topic, error: error)
            return
        }
        cleanupTopicState(topic)
        failPendingRequests(forTopic: topic, error: .sessionExpired)
        await relayClient.unsubscribe(topic: topic)
        ackPeerRequest(id: id, topic: topic, symKey: symKey, tag: WalletConnectSignTag.sessionUpdateResponse)
        eventsContinuation.yield(.sessionDeleted(WalletSessionID(rawValue: topic)))
    }

    /// Applies a wallet-initiated `wc_sessionExtend`: adopts the new expiry when
    /// it is valid — not earlier than the current expiry and within the 7-day
    /// protocol cap (mirrors reown's `WCSession.updateExpiry(to:)`). An
    /// out-of-range or shrinking expiry is ignored (not acked as success). On a
    /// valid extend it re-persists, acks, and emits `.sessionUpdated`.
    private func handleExtend(topic: String, id: Int64, symKey: Data, params: WalletJSONValue?) async {
        guard let existing = sessionsByTopic[topic] else { return }
        guard let params, let extend = try? params.decoded(as: WCExtendParams.self) else { return }

        let newExpiry = Date(timeIntervalSince1970: TimeInterval(extend.expiry))
        let maxExpiry = now().addingTimeInterval(maxSessionLifetime)
        guard newExpiry >= existing.expiryDate, newExpiry <= maxExpiry else { return }

        let extended = WalletSession(
            id: existing.id,
            topic: existing.topic,
            providerID: existing.providerID,
            providerName: existing.providerName,
            accounts: existing.accounts,
            namespaces: existing.namespaces,
            connectedAt: existing.connectedAt,
            expiryDate: newExpiry,
            addressVerified: existing.addressVerified
        )
        do {
            try await persist(session: extended, symKey: symKey, pairingTopic: contextByTopic[topic]?.pairingTopic ?? topic)
        } catch {
            return
        }
        sessionsByTopic[topic] = extended
        ackPeerRequest(id: id, topic: topic, symKey: symKey, tag: WalletConnectSignTag.sessionExtendResponse)
        eventsContinuation.yield(.sessionUpdated(extended))
    }

    /// Surfaces a wallet-emitted `wc_sessionEvent` (e.g. `accountsChanged`,
    /// `chainChanged`) to the host as `.sessionEvent`, then acks. Only delivered
    /// on a live session topic; the event is informational — it does not mutate
    /// the session's account set (a wallet that wants that sends `wc_sessionUpdate`).
    private func handleEvent(topic: String, id: Int64, symKey: Data, params: WalletJSONValue?) {
        guard sessionsByTopic[topic] != nil else { return }
        ackPeerRequest(id: id, topic: topic, symKey: symKey, tag: WalletConnectSignTag.sessionEventResponse)
        guard let params, let event = try? params.decoded(as: WCEventParams.self) else { return }
        let payload = Self.jsonString(from: event.event.data)
        eventsContinuation.yield(
            .sessionEvent(
                WalletSessionEvent(
                    name: event.event.name,
                    topic: WalletPairingTopic(rawValue: topic),
                    chain: WalletBlockchain(caip2: event.chainId),
                    payload: payload,
                    receivedAt: now()
                )
            )
        )
    }

    private func handleProposeResponse(id: Int64, senderPublicKey: Data?, rpc: WalletConnectRPCEnvelope) {
        guard let pending = pendingProposalByID.removeValue(forKey: id) else { return }

        if let error = rpc.error {
            proposalTimeoutTasks.removeValue(forKey: id)?.cancel()
            cleanupTopicState(pending.pairingTopic)
            eventsContinuation.yield(.sessionRejected(pending.providerID, Self.mapError(code: error.code, message: error.message)))
            return
        }

        guard let result = rpc.result ?? rpc.params,
              let response = try? result.decoded(as: WCProposeResponse.self),
              // When the response arrived as a type1 envelope, the key used to
              // decrypt it (envelope sender key) and the key used to derive the
              // session symmetric key (body responderPublicKey) must be the same
              // party. Reject a mismatch so the two independent keys cannot be
              // confused.
              Self.senderMatchesResponder(senderPublicKey, response.responderPublicKey),
              let selfKey = selfKeyByTopic[pending.pairingTopic],
              let sessionSymKey = try? WalletConnectV2Crypto.deriveSymmetricKey(
                  privateKey: selfKey,
                  peerPublicKeyHex: response.responderPublicKey
              ) else {
            proposalTimeoutTasks.removeValue(forKey: id)?.cancel()
            cleanupTopicState(pending.pairingTopic)
            eventsContinuation.yield(.sessionRejected(pending.providerID, .invalidResponse))
            return
        }

        let sessionTopic = WalletConnectV2Crypto.topic(forSymmetricKey: sessionSymKey)
        symKeyByTopic[sessionTopic] = sessionSymKey
        selfKeyByTopic[sessionTopic] = selfKey
        contextByTopic[sessionTopic] = SessionContext(
            providerID: pending.providerID,
            pairingTopic: pending.pairingTopic,
            allowedChains: pending.allowedChains,
            requiredNamespaces: pending.requiredNamespaces
        )

        // The proposal is answered, but the session is not live until settle
        // arrives; keep the pairing-window timeout running and track the
        // in-flight connection so a failed subscribe can be surfaced.
        connectingByProposalID[id] = ConnectingSession(pairing: pending.pairing, providerID: pending.providerID, sessionTopic: sessionTopic)
        proposalIDBySessionTopic[sessionTopic] = id

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.relayClient.subscribe(topic: sessionTopic)
            } catch {
                await self.failConnecting(id: id, error: .relayDisconnected)
            }
        }
    }

    private func handleSettle(topic: String, id: Int64, symKey: Data, params: WalletJSONValue?) async {
        guard let params, let settle = try? params.decoded(as: WCSettleParams.self) else { return }

        // Bind settle to the derived session topic of a pending proposal (or an
        // already-live session, handled by the re-settle branch below). A settle
        // injected on some other topic — e.g. the pairing topic, whose symKey is
        // in the URI in cleartext — is rejected instead of emitting
        // `.sessionApproved` with attacker-chosen accounts.
        guard proposalIDBySessionTopic[topic] != nil || sessionsByTopic[topic] != nil else { return }

        // A settle for a topic that is already live and no longer tied to an
        // in-flight proposal is a re-settle from the peer. Ack it so the wallet
        // stops retrying, but do NOT overwrite the established account set or
        // re-emit `.sessionApproved` — that would let a peer silently swap the
        // session's accounts after it settled.
        if sessionsByTopic[topic] != nil, proposalIDBySessionTopic[topic] == nil {
            ackPeerRequest(id: id, topic: topic, symKey: symKey, tag: WalletConnectSignTag.sessionSettleResponse)
            return
        }

        // Reject an already-expired settle rather than persisting a dead session
        // that would be resurrected (then immediately pruned) on next launch.
        // Clamp a peer-supplied far-future expiry to the 7-day protocol cap so it
        // cannot keep key material / a live subscription alive indefinitely.
        let requestedExpiry = Date(timeIntervalSince1970: TimeInterval(settle.expiry))
        let expiryDate = min(requestedExpiry, now().addingTimeInterval(maxSessionLifetime))
        guard requestedExpiry > now() else {
            if let proposalID = proposalIDBySessionTopic.removeValue(forKey: topic) {
                proposalTimeoutTasks.removeValue(forKey: proposalID)?.cancel()
                let connecting = connectingByProposalID.removeValue(forKey: proposalID)
                if let providerID = connecting?.providerID ?? contextByTopic[topic]?.providerID {
                    eventsContinuation.yield(.sessionRejected(providerID, .sessionExpired))
                }
            }
            return
        }

        // Constrain the settled accounts to the chains this dApp actually
        // proposed. A wallet must not settle accounts on chains we never asked
        // for (or inject extra well-formed addresses on unrequested chains); drop
        // any such account so it can never surface as a trusted address. An empty
        // allow-list means the caller proposed no constraint — accept as-is.
        let (accounts, namespaces) = Self.scopedAccountsAndNamespaces(
            settle.namespaces,
            allowedChains: contextByTopic[topic]?.allowedChains ?? []
        )
        guard !accounts.isEmpty, namespaces.contains(where: { !$0.accounts.isEmpty }) else {
            rejectPendingSettle(topic: topic, error: .invalidResponse)
            return
        }
        do {
            try Self.validateRequiredNamespaces(
                contextByTopic[topic]?.requiredNamespaces ?? .empty,
                against: namespaces
            )
        } catch {
            rejectPendingSettle(topic: topic, error: .invalidResponse)
            return
        }

        // The fallback name is peer-supplied (from the wallet's settle metadata);
        // it is only used when we have no local context for this topic.
        let providerID = contextByTopic[topic]?.providerID ?? WalletProviderID(rawValue: settle.controller.metadata.name.lowercased())
        let session = WalletSession(
            id: WalletSessionID(rawValue: topic),
            topic: WalletPairingTopic(rawValue: topic),
            providerID: providerID,
            providerName: settle.controller.metadata.name,
            accounts: accounts,
            namespaces: namespaces,
            connectedAt: now(),
            expiryDate: expiryDate
        )

        do {
            try await persist(session: session, symKey: symKey, pairingTopic: contextByTopic[topic]?.pairingTopic ?? topic)
        } catch {
            return
        }
        sessionsByTopic[topic] = session

        // The session is live: close the pairing-window timeout and persist the
        // full protocol state so it survives a relaunch.
        if let proposalID = proposalIDBySessionTopic.removeValue(forKey: topic) {
            proposalTimeoutTasks.removeValue(forKey: proposalID)?.cancel()
            connectingByProposalID.removeValue(forKey: proposalID)
        }

        ackPeerRequest(id: id, topic: topic, symKey: symKey, tag: WalletConnectSignTag.sessionSettleResponse)
        eventsContinuation.yield(.sessionApproved(session))

        // The pairing topic has done its job once the session is live. This
        // transport mints a fresh pairing per `createPairing` and never reuses one,
        // so keeping the pairing topic subscribed leaves its symKey — a bearer
        // secret shared out-of-band via the URI — as a live, decryptable surface for
        // the client's whole lifetime. Tear it down so post-settle traffic must ride
        // the session key. `cleanupTopicState` only touches the pairing topic; the
        // session's own keys live under `topic`.
        if let pairingTopic = contextByTopic[topic]?.pairingTopic, pairingTopic != topic {
            cleanupTopicState(pairingTopic)
            Task { [weak self] in await self?.relayClient.unsubscribe(topic: pairingTopic) }
        }
    }

    private func handleRequestResponse(id: Int64, topic: String, rpc: WalletConnectRPCEnvelope) {
        // Only accept a response on the topic the request was published on. A
        // second connected wallet cannot resolve another session's in-flight
        // request by guessing its JSON-RPC id, because its forged response
        // arrives on a different topic than the one bound to that id.
        guard requestTopicByWireID[id] == topic else { return }
        let requestID = WalletSignRequestID(rawValue: String(id))
        if let error = rpc.error {
            Task { await pendingRequests.fail(requestID, error: Self.mapError(code: error.code, message: error.message)) }
            return
        }
        guard let result = rpc.result ?? rpc.params else {
            Task { await pendingRequests.fail(requestID, error: WalletConnectionError.invalidResponse) }
            return
        }
        let resultString = Self.jsonString(from: result)
        Task { await pendingRequests.resolve(WalletResponse(id: requestID, result: resultString)) }
    }

    // MARK: - Outbound helpers

    private func publishRequest(
        method: String,
        params: some Encodable,
        id: Int64,
        tag: Int,
        topic: String,
        symKey: Data,
        ttl: Int? = nil
    ) async throws {
        let message = try Self.sealedType0Message(method: method, params: params, id: id, symKey: symKey)
        try await relayClient.publish(
            WalletConnectRelayPublish(topic: topic, message: message, tag: tag, ttl: ttl ?? WalletConnectSignTag.ttl(for: tag))
        )
    }

    /// Encodes and ChaCha20-Poly1305-seals a type0 request envelope. Extracted so
    /// a caller can build the sealed message on the actor and then publish it from
    /// a detached task that no longer needs `self` (see `disconnect`, where the
    /// remote `wc_sessionDelete` must survive the transport being deallocated).
    private static func sealedType0Message(
        method: String,
        params: some Encodable,
        id: Int64,
        symKey: Data
    ) throws -> String {
        let request = WalletConnectJSONRPCRequest(id: id, method: method, params: params)
        let json = try WalletConnectJSONCoding.encoder.encode(request)
        let sealbox = try WalletConnectV2Crypto.seal(plaintext: json, symKey: symKey)
        return WalletConnectEnvelope(type: .type0, sealbox: sealbox).base64EncodedString()
    }

    private func ackPeerRequest(id: Int64, topic: String, symKey: Data, tag: Int) {
        struct Ack: Encodable {
            let id: Int64
            let jsonrpc = "2.0"
            let result = true
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let json = try WalletConnectJSONCoding.encoder.encode(Ack(id: id))
                let sealbox = try WalletConnectV2Crypto.seal(plaintext: json, symKey: symKey)
                let message = WalletConnectEnvelope(type: .type0, sealbox: sealbox).base64EncodedString()
                try await self.relayClient.publish(
                    WalletConnectRelayPublish(topic: topic, message: message, tag: tag, ttl: WalletConnectSignTag.ttl(for: tag), prompt: false)
                )
            } catch {
                await self.yieldPeerAcknowledgementFailure(topic: topic, id: id, tag: tag, error: error)
            }
        }
    }

    private func yieldPeerAcknowledgementFailure(topic: String, id: Int64, tag: Int, error: Error) {
        let mappedError = error as? WalletConnectionError ?? WalletConnectionError.internalFailure(error.localizedDescription)
        eventsContinuation.yield(
            .peerAcknowledgementFailed(
                WalletPeerAcknowledgementFailure(
                    topic: WalletPairingTopic(rawValue: topic),
                    requestID: id,
                    tag: tag,
                    error: mappedError
                )
            )
        )
    }

    private func relayTTL(forRequestExpiringAt expiryDate: Date) -> Int {
        let interval = max(minimumRequestExpiryInterval, min(maximumRequestExpiryInterval, expiryDate.timeIntervalSince(now())))
        return Int(ceil(interval))
    }

    /// Records the signature of an inbound message and reports whether it is new.
    /// Returns `false` for an already-seen (still-live) message so the caller can
    /// drop it. Signatures expire after `seenMessageTTL`; a hard cap bounds memory.
    private func registerInboundMessage(_ message: String) -> Bool {
        let signature = SHA256.hash(data: Data(message.utf8)).map { String(format: "%02x", $0) }.joined()
        let currentTime = now()
        // Evict signatures older than the TTL so the map tracks only messages the
        // relay could still redeliver.
        while let oldest = seenMessageOrder.first,
              let seenAt = seenMessageAt[oldest],
              currentTime.timeIntervalSince(seenAt) > seenMessageTTL {
            seenMessageOrder.removeFirst()
            seenMessageAt.removeValue(forKey: oldest)
        }
        guard seenMessageAt[signature] == nil else { return false }
        seenMessageAt[signature] = currentTime
        seenMessageOrder.append(signature)
        // Belt-and-suspenders bound: drop the oldest if a flood outpaces the TTL.
        while seenMessageOrder.count > maxSeenMessages {
            let evicted = seenMessageOrder.removeFirst()
            seenMessageAt.removeValue(forKey: evicted)
        }
        return true
    }

    // Internal (not private) so the id-uniqueness invariant is unit-testable.
    func nextID() -> Int64 {
        counter += 1
        // These ids go to the WALLET (wc_sessionPropose / wc_sessionRequest /
        // wc_sessionPing / wc_sessionExtend), so they must survive a JavaScript /
        // React-Native JSON parser that stores numbers as IEEE-754 doubles: an id
        // above `Number.MAX_SAFE_INTEGER` (2^53) is silently rounded by such a
        // wallet, which then echoes a DIFFERENT id in its response and our
        // `handleRequestResponse` topic/id binding never matches (the request
        // hangs to expiry). Mirror reown-swift `JSONRPC/RPCID` (the Sign tier):
        // `ms * 1_000` + 3 random digits ≈ 1.8e15, comfortably under 2^53. This is
        // deliberately a smaller multiplier than the relay client's `nextRequestID`
        // (`ms * 1_000_000`), which talks only to the Rust relay that preserves
        // full Int64 precision. Topic binding in `handleRequestResponse` remains
        // the real response-injection defense; the id is not treated as a secret.
        let millis = Int64(now().timeIntervalSince1970 * 1000)
        let entropy = Int64(Self.randomLowOrder(upperBound: 1_000) ?? UInt32(truncatingIfNeeded: counter) % 1_000)
        let candidate = millis * 1_000 + entropy
        // Clamp against the last id so a backward wall-clock adjustment (NTP) or
        // a repeated random draw can never produce a duplicate or out-of-order id.
        let id = max(candidate, lastIssuedID + 1)
        lastIssuedID = id
        return id
    }

    /// A cryptographically-random value in `0..<upperBound`, or `nil` if the RNG
    /// is unavailable (the caller falls back to the monotonic counter).
    private static func randomLowOrder(upperBound: UInt32) -> UInt32? {
        var raw: UInt32 = 0
        let status = withUnsafeMutableBytes(of: &raw) { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { return nil }
        return raw % upperBound
    }

    // MARK: - Session lifecycle helpers

    /// Removes every live session whose expiry has passed, tearing down its local
    /// state, persisted record, and relay subscription.
    private func pruneExpiredSessions() async throws {
        let expired = sessionsByTopic.filter { $0.value.expiryDate <= now() }.map(\.key)
        for topic in expired {
            try await pruneSession(topic: topic)
        }
    }

    /// Tears down a single expired session: local state, persisted record, and the
    /// relay subscription.
    private func pruneSession(topic: String) async throws {
        try await stateStore.delete(sessionTopic: topic)
        cleanupTopicState(topic)
        // A session that expired out from under an in-flight request should fail
        // that request immediately rather than after its (now moot) expiry.
        failPendingRequests(forTopic: topic, error: .sessionExpired)
        await relayClient.unsubscribe(topic: topic)
    }

    private func cleanupTopicState(_ topic: String) {
        sessionsByTopic.removeValue(forKey: topic)
        symKeyByTopic.removeValue(forKey: topic)
        selfKeyByTopic.removeValue(forKey: topic)
        contextByTopic.removeValue(forKey: topic)
        keepAliveUnresponsiveTopics.remove(topic)
    }

    private func yieldPersistenceDeleteFailure(topic: String, error: Error) {
        guard let providerID = sessionsByTopic[topic]?.providerID ?? contextByTopic[topic]?.providerID else { return }
        eventsContinuation.yield(
            .sessionRejected(
                providerID,
                .internalFailure("Failed to delete persisted WalletConnect session: \(error.localizedDescription)")
            )
        )
    }

    /// Fails every in-flight `request(...)` bound to `topic` so a caller awaiting
    /// a signing response does not hang until its expiry after the session is
    /// torn down (peer delete, local disconnect, or expiry). The
    /// wire-id → topic binding identifies exactly which pending requests belong
    /// to the dead topic; `reject` (not `fail`) is used so the outcome is not
    /// buffered for a future waiter that will never come.
    private func failPendingRequests(forTopic topic: String, error: WalletConnectionError) {
        let wireIDs = requestTopicByWireID.compactMap { $0.value == topic ? $0.key : nil }
        guard !wireIDs.isEmpty else { return }
        for wireID in wireIDs {
            requestTopicByWireID.removeValue(forKey: wireID)
        }
        Task { [pendingRequests] in
            for wireID in wireIDs {
                await pendingRequests.reject(WalletSignRequestID(rawValue: String(wireID)), error: error)
            }
        }
    }

    private func persist(session: WalletSession, symKey: Data, pairingTopic: String) async throws {
        let selfKeyHex = selfKeyByTopic[session.topic.rawValue].map {
            WalletConnectV2Crypto.hexString($0.rawRepresentation)
        }
        let record = WalletConnectPersistedSession(
            sessionTopic: session.topic.rawValue,
            pairingTopic: pairingTopic,
            sessionSymmetricKeyHex: WalletConnectV2Crypto.hexString(symKey),
            selfPrivateKeyHex: selfKeyHex,
            providerID: session.providerID,
            providerName: session.providerName,
            accounts: session.accounts,
            namespaces: session.namespaces,
            requiredNamespaces: contextByTopic[session.topic.rawValue]?.requiredNamespaces,
            allowedChains: contextByTopic[session.topic.rawValue]?.allowedChains,
            connectedAt: session.connectedAt,
            expiryDate: session.expiryDate,
            addressVerified: session.addressVerified
        )
        try await stateStore.save(record)
    }

    private func scheduleProposalTimeout(id: Int64, pairing: WalletPairing) {
        proposalTimeoutTasks[id] = Task { [weak self, expiry = pairing.expiryDate] in
            let delay = max(0, expiry.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            await self?.timeoutProposal(id: id)
        }
    }

    /// Fires at the pairing expiry if the proposal never produced a settled
    /// session — whether the wallet never answered or answered but never
    /// settled. Reports `.pairingExpired` instead of leaving the caller hanging.
    private func timeoutProposal(id: Int64) {
        proposalTimeoutTasks.removeValue(forKey: id)
        let pending = pendingProposalByID.removeValue(forKey: id)
        let connecting = connectingByProposalID.removeValue(forKey: id)
        guard let pairing = pending?.pairing ?? connecting?.pairing else { return }

        if let sessionTopic = connecting?.sessionTopic {
            proposalIDBySessionTopic.removeValue(forKey: sessionTopic)
            cleanupTopicState(sessionTopic)
            Task { [weak self] in await self?.relayClient.unsubscribe(topic: sessionTopic) }
        }
        cleanupTopicState(pairing.topic.rawValue)
        Task { [weak self] in await self?.relayClient.unsubscribe(topic: pairing.topic.rawValue) }
        eventsContinuation.yield(.pairingExpired(pairing))
    }

    /// The proposal was answered but we could not join the session topic, so the
    /// wallet's settle will never reach us. Tear down and report a rejection.
    private func failConnecting(id: Int64, error: WalletConnectionError) {
        proposalTimeoutTasks.removeValue(forKey: id)?.cancel()
        guard let connecting = connectingByProposalID.removeValue(forKey: id) else { return }
        proposalIDBySessionTopic.removeValue(forKey: connecting.sessionTopic)
        cleanupTopicState(connecting.sessionTopic)
        cleanupTopicState(connecting.pairing.topic.rawValue)
        eventsContinuation.yield(.sessionRejected(connecting.providerID, error))
    }

    private func rejectPendingSettle(topic: String, error: WalletConnectionError) {
        guard let proposalID = proposalIDBySessionTopic.removeValue(forKey: topic) else {
            cleanupTopicState(topic)
            return
        }
        proposalTimeoutTasks.removeValue(forKey: proposalID)?.cancel()
        let connecting = connectingByProposalID.removeValue(forKey: proposalID)
        let providerID = connecting?.providerID ?? contextByTopic[topic]?.providerID
        cleanupTopicState(topic)
        if let pairingTopic = connecting?.pairing.topic.rawValue {
            cleanupTopicState(pairingTopic)
        }
        if let providerID {
            eventsContinuation.yield(.sessionRejected(providerID, error))
        }
    }

    // MARK: - Mapping helpers

    private static func validateRequiredNamespaces(
        _ requiredNamespaces: WalletNamespaceProposalSet,
        against settledNamespaces: [WalletSessionNamespace]
    ) throws {
        guard !requiredNamespaces.isEmpty else { return }
        let settledByName = Dictionary(uniqueKeysWithValues: settledNamespaces.map { ($0.name, $0) })
        for (name, required) in requiredNamespaces.proposals {
            guard let settled = settledByName[name] else {
                throw WalletConnectionError.invalidResponse
            }
            guard Set(required.methods).isSubset(of: Set(settled.methods)) else {
                throw WalletConnectionError.invalidResponse
            }
            guard Set(required.events).isSubset(of: Set(settled.events)) else {
                throw WalletConnectionError.invalidResponse
            }
            for chain in required.chains {
                let hasAccountOnChain = settled.accounts.contains { account in
                    guard let parsed = account.parsed else { return false }
                    return chainMatches(parsed.blockchain, chain)
                }
                guard hasAccountOnChain else {
                    throw WalletConnectionError.invalidResponse
                }
            }
        }
    }

    private static func chainMatches(_ granted: WalletBlockchain, _ requested: WalletBlockchain) -> Bool {
        if granted.caip2 == requested.caip2 { return true }
        guard let grantedKnown = granted.knownChain, let requestedKnown = requested.knownChain else { return false }
        return grantedKnown == requestedKnown
    }

    /// The set of CAIP-2 chain identifiers (with known-chain aliases) across every
    /// proposed namespace. Empty when nothing was proposed, which callers treat as
    /// "no constraint".
    private static func allowedChainIdentifiers(_ sets: WalletNamespaceProposalSet...) -> Set<String> {
        var result: Set<String> = []
        for set in sets {
            for proposal in set.proposals.values {
                for chain in proposal.chains {
                    result.insert(chain.caip2)
                    if let known = chain.knownChain {
                        result.formUnion(known.caip2Values)
                    }
                }
            }
        }
        return result
    }

    private static func allowedChainIdentifiers(from accounts: [WalletAccount]) -> Set<String> {
        var result: Set<String> = []
        for account in accounts {
            guard let blockchain = account.parsed?.blockchain else { continue }
            result.insert(blockchain.caip2)
            if let known = blockchain.knownChain {
                result.formUnion(known.caip2Values)
            }
        }
        return result
    }

    /// Collapses a peer-supplied namespace map that may be keyed by chain-scoped
    /// identifiers (`eip155:1`) into one keyed by the bare namespace (`eip155`),
    /// unioning chains/accounts/methods/events across every key that shares a
    /// namespace. CAIP-25 permits a wallet to return either shape; without this
    /// collapse a chain-keyed settle would never match `request.chain.namespace`
    /// in grant / required-namespace validation and the session would settle but
    /// be unsignable. First-seen order is preserved for deterministic output.
    private static func normalizedNamespaceMap(_ namespaceMap: [String: WCSessionNamespace]) -> [String: WCSessionNamespace] {
        struct Accumulator {
            var chains: [String] = []
            var accounts: [String] = []
            var methods: [String] = []
            var events: [String] = []
            private var seenChains = Set<String>()
            private var seenAccounts = Set<String>()
            private var seenMethods = Set<String>()
            private var seenEvents = Set<String>()

            mutating func merge(_ namespace: WCSessionNamespace) {
                for chain in namespace.chains ?? [] where seenChains.insert(chain).inserted { chains.append(chain) }
                for account in namespace.accounts where seenAccounts.insert(account).inserted { accounts.append(account) }
                for method in namespace.methods where seenMethods.insert(method).inserted { methods.append(method) }
                for event in namespace.events where seenEvents.insert(event).inserted { events.append(event) }
            }
        }

        var accumulators: [String: Accumulator] = [:]
        for (key, namespace) in namespaceMap.sorted(by: { $0.key < $1.key }) {
            let bareNamespace = key.split(separator: ":", maxSplits: 1).first.map(String.init) ?? key
            accumulators[bareNamespace, default: Accumulator()].merge(namespace)
        }
        return accumulators.mapValues { accumulator in
            WCSessionNamespace(
                chains: accumulator.chains.isEmpty ? nil : accumulator.chains,
                accounts: accumulator.accounts,
                methods: accumulator.methods,
                events: accumulator.events
            )
        }
    }

    /// Maps a peer-supplied namespace map (from `wc_sessionSettle` or
    /// `wc_sessionUpdate`) into deduplicated accounts and sorted session
    /// namespaces, dropping any account on a chain outside `allowedChains`. Shared
    /// by settle and update so both apply the identical chain-scoping guard.
    private static func scopedAccountsAndNamespaces(
        _ namespaceMap: [String: WCSessionNamespace],
        allowedChains: Set<String>
    ) -> (accounts: [WalletAccount], namespaces: [WalletSessionNamespace]) {
        var seen = Set<String>()
        var accounts: [WalletAccount] = []
        var namespaces: [WalletSessionNamespace] = []
        // Collapse any chain-scoped keys (`eip155:1`) to their bare namespace
        // (`eip155`) first, so a wallet that keys settle/update by CAIP-2 still
        // matches the namespace-keyed grant/required-namespace validation below.
        for (name, namespace) in Self.normalizedNamespaceMap(namespaceMap).sorted(by: { $0.key < $1.key }) {
            let nsAccounts = namespace.accounts
                .map(WalletAccount.init(caip10:))
                .filter { Self.isAccountAllowed($0, allowedChains: allowedChains) }
            for account in nsAccounts where seen.insert(account.caip10).inserted {
                accounts.append(account)
            }
            namespaces.append(
                WalletSessionNamespace(
                    name: name,
                    accounts: nsAccounts,
                    methods: namespace.methods.sorted(),
                    events: namespace.events.sorted()
                )
            )
        }
        return (accounts, namespaces)
    }

    /// Whether a settled account sits on a chain the dApp proposed. With no
    /// constraint every account is allowed; otherwise a malformed account (one we
    /// cannot parse to a known chain) is rejected so it can never be trusted.
    private static func isAccountAllowed(_ account: WalletAccount, allowedChains: Set<String>) -> Bool {
        guard !allowedChains.isEmpty else { return true }
        guard let parsed = account.parsed else { return false }
        if allowedChains.contains(parsed.blockchain.caip2) { return true }
        if let known = parsed.blockchain.knownChain, !known.caip2Values.isDisjoint(with: allowedChains) {
            return true
        }
        return false
    }

    private static func proposalNamespaces(_ set: WalletNamespaceProposalSet) -> [String: WCProposalNamespace] {
        set.proposals.mapValues { proposal in
            WCProposalNamespace(
                chains: proposal.chains.map { $0.caip2 },
                methods: proposal.methods,
                events: proposal.events
            )
        }
    }

    /// For a type1 propose-response, the envelope sender key and the body's
    /// `responderPublicKey` must be the same party. `nil` sender (type0) skips the
    /// check, since a type0 envelope carries no sender key to compare against.
    private static func senderMatchesResponder(_ senderPublicKey: Data?, _ responderPublicKeyHex: String) -> Bool {
        guard let senderPublicKey else { return true }
        return WalletConnectV2Crypto.hexString(senderPublicKey).caseInsensitiveCompare(responderPublicKeyHex) == .orderedSame
    }

    private static func mapError(code: Int, message: String) -> WalletConnectionError {
        switch code {
        case 4001, 5000:
            return .userRejected
        default:
            return .internalFailure(message)
        }
    }

    private static func jsonString(from value: WalletJSONValue) -> String {
        if case .string(let string) = value { return string }
        guard let data = try? WalletConnectJSONCoding.encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    private static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        // A non-success status leaves `bytes` all zero, which would yield a
        // predictable symmetric key (and topic). Fail loudly instead.
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw WalletConnectionError.cryptographyFailure
        }
        return Data(bytes)
    }
}
