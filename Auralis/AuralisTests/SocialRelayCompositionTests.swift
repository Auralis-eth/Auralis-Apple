@testable import Auralis
import Foundation
import SocialCore
import Testing

@Suite("Social relay composition")
struct SocialRelayCompositionTests {
    private func enabledConfiguration() -> SocialFeatureConfiguration {
        SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true])
    }

    private func makeEnvelope(
        sessionID: UUID,
        id: UUID = UUID(),
        author: String,
        event: SocialEvent = .receiptShared(UUID())
    ) -> SocialEventEnvelope {
        SocialEventEnvelope(
            id: id,
            sessionID: sessionID,
            authorParticipantID: author,
            authorCAIP10Account: "eip155:1:0x\(author)",
            event: event
        )
    }

    /// A join event in which `author` claims to be a verified, vote-capable participant.
    ///
    /// `participantJoined` is deliberately the one binding-ish event that does *not* require an
    /// already verified author (see `SocialEvent.requiresVerifiedAuthor`), so it is what bootstraps
    /// membership over the wire for a peer nobody has seen before.
    ///
    /// What it bootstraps is *membership*, not authority. The `.verified` claim here is self-asserted
    /// — the relay seals with one shared session key, so the transport proves invite possession and
    /// nothing about whose wallet signed what — and the projection downgrades it to `.pending` on
    /// arrival. The peer becomes visible; it does not become an author.
    private func makeJoin(sessionID: UUID, author: String) -> SocialEventEnvelope {
        makeEnvelope(
            sessionID: sessionID,
            author: author,
            event: .participantJoined(
                SocialParticipantIdentity(
                    participantID: author,
                    caip10Account: "eip155:1:0x\(author)",
                    displayName: author.capitalized,
                    role: .collaborator,
                    verificationState: .verified,
                    proofID: "proof.\(author)"
                )
            )
        )
    }

    @Test("end-to-end: subscribe, publish real-encrypted outbound, receive inbound through the pump")
    func endToEnd() async throws {
        let store = SocialEventLogStore()
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")
        await store.saveInvite(invite)

        let composition = SocialRelayComposition(configuration: enabledConfiguration(), eventLogStore: store)
        let transport = FakeRelayTransport()
        let inbound = ControllableInboundSource()
        let inboundProcessed = AsyncSignal()
        let runtime = try #require(
            try composition.makeSession(
                for: invite,
                transport: transport,
                inboundSource: inbound,
                onInboundProcessed: { await inboundProcessed.signal() }
            )
        )

        try await runtime.start()

        // Subscribed to exactly the invite's opaque topic.
        #expect(await transport.subscribedTopics() == [invite.relayTopic])

        // Outbound: enqueue a local event, flush it, and confirm the wire payload is real ciphertext that
        // decrypts back to the event with the invite's key.
        let outbound = makeEnvelope(sessionID: invite.sessionID, author: "alice")
        await store.enqueueOutbound(outbound)
        try await runtime.coordinator.publishPendingOutbound()

        let published = try #require(await transport.publishedMessages().first)
        #expect(published.topic == invite.relayTopic)
        // Bound exactly as a real peer's cipher is: built from the same invite, so it carries the same
        // session id and relay topic and can verify the v2 associated data the payload is sealed with.
        let cipher = try SocialEnvelopeCipher(
            base64EncodedSessionKey: invite.encryptedSessionKey,
            sessionID: invite.sessionID,
            relayTopic: invite.relayTopic
        )
        #expect(published.message != outbound.id.uuidString) // opaque on the wire
        #expect(try cipher.open(published.message) == outbound)
        #expect(await store.pendingOutbound().isEmpty)

        // Inbound: a peer joins and the pump drains the sealed payload into the log, which is the
        // round trip this test exists to cover — subscribe, decrypt, evaluate, append.
        let join = makeJoin(sessionID: invite.sessionID, author: "bob")
        inbound.push(topic: invite.relayTopic, message: try cipher.seal(join))
        await inboundProcessed.wait()
        #expect(await store.allEnvelopes().contains(join))

        // But the join does not make Bob an author. His record claimed `.verified` — "a wallet
        // signed this session's join challenge" — and that is a claim about an event on his device
        // which the envelope cannot prove, so the projection downgrades it to `.pending`. Holding
        // the session key and asserting verification is not authority to write.
        let projection = await store.projection(sessionID: invite.sessionID)
        #expect(projection.participants["bob"]?.verificationState == .pending)
        #expect(projection.participants["bob"]?.canAuthorBindingEvents == false)

        // So his binding event is refused rather than appended. This is the accepted v1 posture: a
        // peer must be verified by *this* installation before it can share. It lifts when the proof
        // travels with the identity — see `SocialSessionProjection.downgradedVerification`.
        let remote = makeEnvelope(sessionID: invite.sessionID, author: "bob")
        #expect(projection.rejectionReason(for: remote) == .unverifiedAuthor)
        inbound.push(topic: invite.relayTopic, message: try cipher.seal(remote))
        await inboundProcessed.wait()

        #expect(await store.allEnvelopes().contains(remote) == false)

        await runtime.stop()
    }

    @Test("inbound from a non-member is dropped even when sealed with the real session key")
    func unjoinedAuthorInboundDropped() async throws {
        let store = SocialEventLogStore()
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")
        await store.saveInvite(invite)

        let composition = SocialRelayComposition(configuration: enabledConfiguration(), eventLogStore: store)
        let inbound = ControllableInboundSource()
        let inboundProcessed = AsyncSignal()
        let runtime = try #require(
            try composition.makeSession(
                for: invite,
                transport: FakeRelayTransport(),
                inboundSource: inbound,
                onInboundProcessed: { await inboundProcessed.signal() }
            )
        )
        try await runtime.start()

        // Correct key, correct topic, but "mallory" never joined. Possession of the session key must not
        // be sufficient to author a binding event, otherwise a leaked invite becomes a write capability.
        let cipher = try SocialEnvelopeCipher(
            base64EncodedSessionKey: invite.encryptedSessionKey,
            sessionID: invite.sessionID,
            relayTopic: invite.relayTopic
        )
        let unjoined = makeEnvelope(sessionID: invite.sessionID, author: "mallory")
        inbound.push(topic: invite.relayTopic, message: try cipher.seal(unjoined))
        await inboundProcessed.wait()
        #expect(await store.allEnvelopes().isEmpty)

        await runtime.stop()
    }

    /// Back-compat for the v2 associated-data change, asserted end-to-end rather than only at the cipher.
    ///
    /// A peer running an earlier build seals without associated data and emits the unprefixed v1 form.
    /// The invite carries the session key, not the format, and there is no re-key path — so if the pump
    /// stopped accepting v1, every session shared with an un-updated peer would go silently deaf.
    @Test("a legacy v1 inbound payload is still accepted by a v2-sealing session")
    func legacyVersion1InboundIsAccepted() async throws {
        let store = SocialEventLogStore()
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")
        await store.saveInvite(invite)

        let composition = SocialRelayComposition(configuration: enabledConfiguration(), eventLogStore: store)
        let inbound = ControllableInboundSource()
        let inboundProcessed = AsyncSignal()
        let runtime = try #require(
            try composition.makeSession(
                for: invite,
                transport: FakeRelayTransport(),
                inboundSource: inbound,
                onInboundProcessed: { await inboundProcessed.signal() }
            )
        )
        try await runtime.start()

        // An old-build peer: same key, no session/topic binding, so `seal` emits the v1 form.
        let legacyPeer = try SocialEnvelopeCipher(base64EncodedSessionKey: invite.encryptedSessionKey)
        let join = makeJoin(sessionID: invite.sessionID, author: "bob")
        let legacyPayload = try legacyPeer.seal(join)
        #expect(!legacyPayload.hasPrefix(SocialEnvelopeCipher.version2Prefix))

        inbound.push(topic: invite.relayTopic, message: legacyPayload)
        await inboundProcessed.wait()

        #expect(await store.allEnvelopes().contains(join))

        await runtime.stop()
    }

    @Test("inbound payload for a foreign key is dropped, not appended (crypto enforces topic membership)")
    func foreignInboundDropped() async throws {
        let store = SocialEventLogStore()
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")
        await store.saveInvite(invite)

        let composition = SocialRelayComposition(configuration: enabledConfiguration(), eventLogStore: store)
        let inbound = ControllableInboundSource()
        let inboundProcessed = AsyncSignal()
        let runtime = try #require(
            try composition.makeSession(
                for: invite,
                transport: FakeRelayTransport(),
                inboundSource: inbound,
                onInboundProcessed: { await inboundProcessed.signal() }
            )
        )
        try await runtime.start()

        // A message sealed with a *different* session key cannot be opened by this session's cipher.
        let foreignCipher = try SocialEnvelopeCipher(base64EncodedSessionKey: SocialSessionKey.generateBase64Encoded())
        let foreign = makeEnvelope(sessionID: invite.sessionID, author: "mallory")
        inbound.push(topic: invite.relayTopic, message: try foreignCipher.seal(foreign))
        await inboundProcessed.wait()

        #expect(await store.allEnvelopes().isEmpty)

        await runtime.stop()
    }

    @Test("disabled relay flag yields no session runtime")
    func disabledYieldsNil() throws {
        let composition = SocialRelayComposition(
            configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": false]),
            eventLogStore: SocialEventLogStore()
        )
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")

        let runtime = try composition.makeSession(
            for: invite,
            transport: FakeRelayTransport(),
            inboundSource: ControllableInboundSource()
        )
        #expect(runtime == nil)
    }

    @Test("malformed invite session key fails closed")
    func invalidKeyFailsClosed() {
        let composition = SocialRelayComposition(configuration: enabledConfiguration(), eventLogStore: SocialEventLogStore())
        let invite = SocialInvite(
            sessionID: UUID(),
            relayTopic: "topic",
            encryptedSessionKey: "not-a-valid-key",
            inviterParticipantID: "alice",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            nonce: "nonce"
        )

        #expect(throws: SocialEnvelopeCipherError.invalidKey) {
            _ = try composition.makeSession(
                for: invite,
                transport: FakeRelayTransport(),
                inboundSource: ControllableInboundSource()
            )
        }
    }

    @Test("minted invite is valid, unexpired, PII-free, and carries a usable key")
    func mintProducesUsableInvite() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice", now: now, ttl: 3_600)

        #expect(!invite.isExpired(now: now))
        #expect(invite.isExpired(now: now.addingTimeInterval(3_601)))
        #expect(invite.relayTopic.count == SocialInviteMint.topicByteCount * 2)
        #expect(invite.nonce.count == SocialInviteMint.nonceByteCount * 2)
        #expect(!invite.relayTopic.contains("alice"))
        _ = try SocialEnvelopeCipher(base64EncodedSessionKey: invite.encryptedSessionKey)
    }

    @Test("each mint uses a fresh topic, nonce, and session key")
    func mintIsUnique() {
        let first = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")
        let second = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "alice")

        #expect(first.relayTopic != second.relayTopic)
        #expect(first.nonce != second.nonce)
        #expect(first.encryptedSessionKey != second.encryptedSessionKey)
    }

}

private actor FakeRelayTransport: SocialRelayTransporting {
    private var topics: [String] = []
    private var messages: [(topic: String, message: String, tag: Int, ttl: Int)] = []

    func subscribe(topic: String) async throws { topics.append(topic) }
    func publish(topic: String, message: String, tag: Int, ttl: Int) async throws {
        messages.append((topic, message, tag, ttl))
    }

    func subscribedTopics() -> [String] { topics }
    func publishedMessages() -> [(topic: String, message: String, tag: Int, ttl: Int)] { messages }
}

private final class ControllableInboundSource: SocialRelayInboundStreaming, @unchecked Sendable {
    private let stream: AsyncStream<SocialRelayInboundMessage>
    private let continuation: AsyncStream<SocialRelayInboundMessage>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: SocialRelayInboundMessage.self)
    }

    func inboundMessages() async -> AsyncStream<SocialRelayInboundMessage> { stream }

    func push(topic: String, message: String) {
        continuation.yield(SocialRelayInboundMessage(topic: topic, message: message))
    }
}

/// A one-shot, race-safe synchronization point for the pump's `onInboundProcessed` callback.
private actor AsyncSignal {
    private var pendingSignalCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func signal() {
        if continuations.isEmpty {
            pendingSignalCount += 1
        } else {
            continuations.removeFirst().resume()
        }
    }

    func wait() async {
        if pendingSignalCount > 0 {
            pendingSignalCount -= 1
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}
