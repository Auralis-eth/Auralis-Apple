@testable import Auralis
import Foundation
import SocialCore
import Testing

@Suite("Social relay coordinator")
struct SocialRelayCoordinatorTests {
    @Test("disabled relay fails closed")
    func disabledRelayFailsClosed() async throws {
        let fixture = RelayFixture(relayEnabled: false)

        await #expect(throws: SocialRelayCoordinatorError.disabled) {
            try await fixture.coordinator.subscribeToSavedInvites()
        }
    }

    @Test("pending outbound publishes encrypted payload and clears the queue")
    func pendingOutboundPublishesAndClearsQueue() async throws {
        let fixture = RelayFixture(relayEnabled: true)
        await fixture.store.saveInvite(fixture.invite)
        await fixture.store.enqueueOutbound(fixture.event)

        try await fixture.coordinator.publishPendingOutbound()

        #expect(await fixture.transport.publishedMessages().count == 1)
        #expect(await fixture.transport.publishedMessages().first?.message == "sealed:" + fixture.event.id.uuidString)
        #expect(await fixture.store.pendingOutbound().isEmpty)
    }

    @Test("inbound payload is opened and appended once")
    func inboundPayloadIsOpenedAndAppended() async throws {
        let fixture = RelayFixture(relayEnabled: true)

        try await fixture.coordinator.handleInbound(message: "sealed:" + fixture.event.id.uuidString, topic: fixture.invite.relayTopic)
        try await fixture.coordinator.handleInbound(message: "sealed:" + fixture.event.id.uuidString, topic: fixture.invite.relayTopic)

        let envelopes = await fixture.store.allEnvelopes()
        #expect(envelopes == [fixture.event])
    }

    @Test("malformed and oversized payloads fail closed")
    func badPayloadsFailClosed() async throws {
        let fixture = RelayFixture(relayEnabled: true, maxPayloadBytes: 12)

        await #expect(throws: SocialRelayCoordinatorError.malformedPayload) {
            try await fixture.coordinator.handleInbound(message: "bad", topic: fixture.invite.relayTopic)
        }
        await #expect(throws: SocialRelayCoordinatorError.oversizedPayload(limitBytes: 12)) {
            try await fixture.coordinator.handleInbound(message: String(repeating: "x", count: 13), topic: fixture.invite.relayTopic)
        }
    }

    /// A coordinator holds one session key, and `SocialEnvelopeCipher.open` carries no session
    /// discriminator — so "it decrypted" proves the sender holds *this* session's invite and nothing
    /// more. Without the binding, the payload's own `sessionID` chose which graph it was appended
    /// to, so an invite holder for one session could write into every other session on the device.
    @Test("an envelope naming a different session is quarantined, not appended")
    func foreignSessionEnvelopeIsQuarantined() async throws {
        let fixture = RelayFixture(relayEnabled: true)
        // A **self-authored new-peer join**, deliberately. The payload has to be one the foreign
        // session's projection would otherwise *accept*, or the test proves nothing: a
        // `.receiptShared` here was refused as `.unverifiedAuthor` anyway — the foreign projection
        // holds no participants — so it passed with the binding removed and was a tautology.
        // Introducing a new peer is the one relay write that is legitimately accepted, which makes
        // it exactly the payload that reached another session's graph before this guard existed.
        let foreignSessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000004FF")!
        let foreign = SocialEventEnvelope(
            sessionID: foreignSessionID,
            authorParticipantID: "mallory",
            createdAt: Date(timeIntervalSince1970: 20),
            event: .participantJoined(
                SocialParticipantIdentity(
                    participantID: "mallory",
                    caip10Account: "eip155:1:0xmallory",
                    displayName: "Mallory",
                    role: .collaborator,
                    verificationState: .pending
                )
            )
        )
        let coordinator = SocialRelayCoordinator(
            configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
            eventLogStore: fixture.store,
            transport: fixture.transport,
            // Decrypts successfully — this session's key really does open it. That is the point.
            cipher: FixtureSocialEnvelopeCipher(envelope: foreign),
            boundSessionID: fixture.sessionID,
            boundTopic: fixture.invite.relayTopic
        )

        try await coordinator.handleInbound(
            message: "sealed:" + foreign.id.uuidString,
            topic: fixture.invite.relayTopic
        )

        #expect(await fixture.store.allEnvelopes().isEmpty)
    }

    /// The same binding on the other axis: a payload for this session arriving on a topic this
    /// coordinator is not subscribed to is not this coordinator's to process.
    @Test("an envelope arriving on a foreign topic is quarantined")
    func foreignTopicIsQuarantined() async throws {
        let fixture = RelayFixture(relayEnabled: true)

        try await fixture.coordinator.handleInbound(
            message: "sealed:" + fixture.event.id.uuidString,
            topic: "topic-somewhere-else"
        )

        #expect(await fixture.store.allEnvelopes().isEmpty)
    }

    /// Outbound scoping. Draining every session's backlog through one coordinator sealed them all
    /// with *this* session's key, so another session's envelope was published on its own correct
    /// topic but encrypted under the wrong key — unreadable by its members — and `markPublished`
    /// cleared it anyway, losing it permanently. The other session's envelope must stay pending for
    /// the coordinator that actually holds its key.
    @Test("another session's pending outbound is neither published nor cleared")
    func foreignSessionOutboundIsLeftPending() async throws {
        let fixture = RelayFixture(relayEnabled: true)
        await fixture.store.saveInvite(fixture.invite)
        await fixture.store.enqueueOutbound(fixture.event)

        let otherSessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000004EE")!
        let otherInvite = SocialInvite(
            sessionID: otherSessionID,
            relayTopic: "topic-b",
            encryptedSessionKey: "ciphertext-b",
            inviterParticipantID: "bob",
            expiresAt: Date(timeIntervalSince1970: 200),
            nonce: "nonce-b"
        )
        let otherEnvelope = SocialEventEnvelope(
            sessionID: otherSessionID,
            authorParticipantID: "bob",
            createdAt: Date(timeIntervalSince1970: 30),
            event: .receiptShared(UUID())
        )
        await fixture.store.saveInvite(otherInvite)
        await fixture.store.enqueueOutbound(otherEnvelope)

        try await fixture.coordinator.publishPendingOutbound()

        let published = await fixture.transport.publishedMessages()
        #expect(published.count == 1)
        #expect(published.first?.topic == fixture.invite.relayTopic)
        // Still queued, for the coordinator bound to session B.
        #expect(await fixture.store.pendingOutbound().map(\.id) == [otherEnvelope.id])
    }

    @Test("inbound rate limiting fails closed after the per-topic window budget")
    func inboundRateLimitingFailsClosed() async throws {
        let fixture = RelayFixture(relayEnabled: true)
        let fixedNow = Date(timeIntervalSince1970: 1_000)
        let coordinator = SocialRelayCoordinator(
            configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
            eventLogStore: fixture.store,
            transport: fixture.transport,
            cipher: FixtureSocialEnvelopeCipher(envelope: fixture.event),
            boundSessionID: fixture.sessionID,
            boundTopic: fixture.invite.relayTopic,
            maxInboundPerWindow: 2,
            now: { fixedNow }
        )
        let sealed = "sealed:" + fixture.event.id.uuidString

        try await coordinator.handleInbound(message: sealed, topic: fixture.invite.relayTopic)
        try await coordinator.handleInbound(message: sealed, topic: fixture.invite.relayTopic)
        await #expect(throws: SocialRelayCoordinatorError.rateLimited(topic: fixture.invite.relayTopic)) {
            try await coordinator.handleInbound(message: sealed, topic: fixture.invite.relayTopic)
        }
    }

    /// A flood on *another* session's topic must not consume this session's budget or degrade it.
    ///
    /// The limiter used to run before the `topic == boundTopic` guard, so inbound traffic for session B
    /// both marked session A `.degraded` in Mission Control and grew an unprunable per-topic bucket —
    /// the cross-session bleed this coordinator was scoped to eliminate. Foreign traffic is now
    /// discarded before it touches any of this session's state.
    @Test("a flood on a foreign topic neither degrades nor rate-limits the bound session")
    func foreignTopicFloodDoesNotAffectBoundSession() async throws {
        let fixture = RelayFixture(relayEnabled: true)
        let fixedNow = Date(timeIntervalSince1970: 1_000)
        let coordinator = SocialRelayCoordinator(
            configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
            eventLogStore: fixture.store,
            transport: fixture.transport,
            cipher: FixtureSocialEnvelopeCipher(envelope: fixture.event),
            boundSessionID: fixture.sessionID,
            boundTopic: fixture.invite.relayTopic,
            maxInboundPerWindow: 2,
            now: { fixedNow }
        )
        let sealed = "sealed:" + fixture.event.id.uuidString
        let foreignTopic = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

        // Far more than the window budget, all on someone else's topic.
        for _ in 0..<50 {
            try await coordinator.handleInbound(message: sealed, topic: foreignTopic)
        }

        // The bound session's budget is untouched: two more arrivals still succeed.
        try await coordinator.handleInbound(message: sealed, topic: fixture.invite.relayTopic)
        try await coordinator.handleInbound(message: sealed, topic: fixture.invite.relayTopic)

        // And the session was never marked degraded by the foreign flood.
        let syncState = await fixture.store.currentSnapshot().syncStates[fixture.sessionID]
        #expect(
            syncState?.phase != .degraded,
            "A foreign-topic flood degraded the bound session: \(String(describing: syncState))"
        )
    }

    /// Every durable diagnostic path is throttled per window, not just the rate-limited one.
    ///
    /// `recordQuarantine` appends a signed, sequenced receipt. The throttle originally guarded the
    /// `.rateLimited` branch alone, which left the amplification it exists to prevent wide open: a
    /// peer who knows the topic (any session member, or the relay operator) could publish junk just
    /// *under* the rate limit, have every message fail `cipher.open`, and mint one permanent ledger
    /// row per message — hundreds of thousands a day from bounded CPU cost. The limiter bounded the
    /// work; nothing bounded the storage.
    @Test("a sustained malformed flood under the rate limit mints one receipt per window, not per message")
    func malformedFloodIsThrottledToOnePerWindow() async throws {
        let fixture = RelayFixture(relayEnabled: true)
        let fixedNow = Date(timeIntervalSince1970: 1_000)
        let diagnostics = CountingSocialRelayDiagnostics()
        let coordinator = SocialRelayCoordinator(
            configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
            eventLogStore: fixture.store,
            transport: fixture.transport,
            cipher: FixtureSocialEnvelopeCipher(envelope: fixture.event),
            boundSessionID: fixture.sessionID,
            boundTopic: fixture.invite.relayTopic,
            // Deliberately generous, so every arrival is *admitted* and reaches the decrypt failure.
            // Throttling only the rate-limited branch would record nothing here and still be wrong.
            maxInboundPerWindow: 10_000,
            now: { fixedNow },
            diagnostics: diagnostics
        )

        for _ in 0..<200 {
            await #expect(throws: SocialRelayCoordinatorError.malformedPayload) {
                try await coordinator.handleInbound(
                    message: "not-a-sealed-payload",
                    topic: fixture.invite.relayTopic
                )
            }
        }

        let malformedCount = await diagnostics.quarantineCount(for: .malformed)
        #expect(malformedCount == 1, "200 malformed payloads minted \(malformedCount) durable receipts")
    }

    /// The same bound on the oversized path, which is the cheapest of all to trigger: it is refused
    /// before any decryption work, so a peer pays almost nothing per receipt it mints.
    @Test("a sustained oversized flood mints one receipt per window")
    func oversizedFloodIsThrottledToOnePerWindow() async throws {
        let fixture = RelayFixture(relayEnabled: true)
        let fixedNow = Date(timeIntervalSince1970: 1_000)
        let diagnostics = CountingSocialRelayDiagnostics()
        let coordinator = SocialRelayCoordinator(
            configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
            eventLogStore: fixture.store,
            transport: fixture.transport,
            cipher: FixtureSocialEnvelopeCipher(envelope: fixture.event),
            boundSessionID: fixture.sessionID,
            boundTopic: fixture.invite.relayTopic,
            maxPayloadBytes: 12,
            maxInboundPerWindow: 10_000,
            now: { fixedNow },
            diagnostics: diagnostics
        )

        for _ in 0..<100 {
            await #expect(throws: SocialRelayCoordinatorError.oversizedPayload(limitBytes: 12)) {
                try await coordinator.handleInbound(
                    message: String(repeating: "x", count: 64),
                    topic: fixture.invite.relayTopic
                )
            }
        }

        #expect(await diagnostics.quarantineCount(for: .oversized) == 1)
    }

    /// Each reason is throttled on its own clock, so a flood of one kind cannot suppress the first
    /// report of another — the throttle must bound volume without blinding the diagnostics.
    @Test("throttling is per reason, so one flood does not mask a different failure")
    func throttlingIsPerReason() async throws {
        let fixture = RelayFixture(relayEnabled: true)
        let fixedNow = Date(timeIntervalSince1970: 1_000)
        let diagnostics = CountingSocialRelayDiagnostics()
        let coordinator = SocialRelayCoordinator(
            configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
            eventLogStore: fixture.store,
            transport: fixture.transport,
            cipher: FixtureSocialEnvelopeCipher(envelope: fixture.event),
            boundSessionID: fixture.sessionID,
            boundTopic: fixture.invite.relayTopic,
            maxPayloadBytes: 32,
            maxInboundPerWindow: 10_000,
            now: { fixedNow },
            diagnostics: diagnostics
        )

        for _ in 0..<20 {
            try? await coordinator.handleInbound(message: "short-bad", topic: fixture.invite.relayTopic)
        }
        try? await coordinator.handleInbound(
            message: String(repeating: "x", count: 64),
            topic: fixture.invite.relayTopic
        )

        #expect(await diagnostics.quarantineCount(for: .malformed) == 1)
        #expect(await diagnostics.quarantineCount(for: .oversized) == 1)
    }

    /// The rate-limit *degrade* is set on every refusal, even when its receipt is throttled.
    ///
    /// With the degrade inside the throttle, a flood that tripped the limit, paused long enough for one
    /// envelope to be accepted (which clears the flag and sets `.connected`), then resumed inside the
    /// same window left Mission Control reporting a healthy session while every message was refused.
    @Test("a renewed flood inside the same window re-degrades the session even though the receipt is throttled")
    func renewedFloodRedegradesWithinWindow() async throws {
        let fixture = RelayFixture(relayEnabled: true)
        let fixedNow = Date(timeIntervalSince1970: 1_000)
        let diagnostics = CountingSocialRelayDiagnostics()
        let coordinator = SocialRelayCoordinator(
            configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
            eventLogStore: fixture.store,
            transport: fixture.transport,
            cipher: FixtureSocialEnvelopeCipher(envelope: fixture.event),
            boundSessionID: fixture.sessionID,
            boundTopic: fixture.invite.relayTopic,
            maxInboundPerWindow: 2,
            now: { fixedNow },
            diagnostics: diagnostics
        )
        let sealed = "sealed:" + fixture.event.id.uuidString
        let topic = fixture.invite.relayTopic

        // Budget of 2: two land, the third trips the limit and degrades.
        try await coordinator.handleInbound(message: sealed, topic: topic)
        try await coordinator.handleInbound(message: sealed, topic: topic)
        try? await coordinator.handleInbound(message: sealed, topic: topic)
        let degradedPhase = await fixture.store.currentSnapshot().syncStates[fixture.sessionID]?.phase
        #expect(degradedPhase == .degraded)

        // The limiter's window never advances here (`now` is fixed), so the budget stays exhausted and
        // every further arrival is refused. The state must keep reporting that.
        try? await coordinator.handleInbound(message: sealed, topic: topic)
        let stillDegraded = await fixture.store.currentSnapshot().syncStates[fixture.sessionID]?.phase
        #expect(stillDegraded == .degraded)

        // And the receipt is still throttled to one for the whole window.
        #expect(await diagnostics.quarantineCount(for: .rateLimited) == 1)
    }
}

/// Counts durable diagnostic emissions by reason, so a test can assert how many receipts a flood
/// would have minted.
private actor CountingSocialRelayDiagnostics: SocialRelayDiagnostics {
    private var quarantines: [SocialRelayQuarantineReason: Int] = [:]
    private var rejectedEvents = 0

    func recordQuarantine(reason: SocialRelayQuarantineReason, topic: String) async {
        quarantines[reason, default: 0] += 1
    }

    func recordRejectedEvent(
        reason: SocialSessionProjection.RejectionReason,
        sessionID: UUID,
        eventID: UUID
    ) async {
        rejectedEvents += 1
    }

    func recordDroppedOutbound(
        reason: SocialRelayQuarantineReason,
        sessionID: UUID,
        eventID: UUID
    ) async { }

    func recordOperationalEvent(_ event: SocialRelayOperationalEvent) async { }

    func quarantineCount(for reason: SocialRelayQuarantineReason) -> Int {
        quarantines[reason] ?? 0
    }

    func rejectedEventCount() -> Int { rejectedEvents }
}

private struct RelayFixture {
    let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
    let invite: SocialInvite
    let event: SocialEventEnvelope
    let store: SocialEventLogStore
    let transport: RecordingSocialRelayTransport
    let coordinator: SocialRelayCoordinator

    init(relayEnabled: Bool, maxPayloadBytes: Int = 16 * 1024) {
        invite = SocialInvite(
            sessionID: sessionID,
            relayTopic: "topic-a",
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: Date(timeIntervalSince1970: 200),
            nonce: "nonce"
        )
        event = SocialEventEnvelope(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
            sessionID: sessionID,
            authorParticipantID: "alice",
            authorCAIP10Account: "eip155:1:0xalice",
            createdAt: Date(timeIntervalSince1970: 10),
            event: .participantJoined(
                SocialParticipantIdentity(
                    participantID: "alice",
                    caip10Account: "eip155:1:0xalice",
                    displayName: "Alice",
                    role: .collaborator,
                    verificationState: .verified,
                    joinedAt: Date(timeIntervalSince1970: 10),
                    proofID: "proof"
                )
            )
        )
        store = SocialEventLogStore()
        transport = RecordingSocialRelayTransport()
        coordinator = SocialRelayCoordinator(
            configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": relayEnabled]),
            eventLogStore: store,
            transport: transport,
            cipher: FixtureSocialEnvelopeCipher(envelope: event),
            boundSessionID: sessionID,
            boundTopic: invite.relayTopic,
            maxPayloadBytes: maxPayloadBytes
        )
    }
}

private actor RecordingSocialRelayTransport: SocialRelayTransporting {
    private var topics: [String] = []
    private var messages: [(topic: String, message: String, tag: Int, ttl: Int)] = []

    func subscribe(topic: String) async throws {
        topics.append(topic)
    }

    func publish(topic: String, message: String, tag: Int, ttl: Int) async throws {
        messages.append((topic, message, tag, ttl))
    }

    func subscribedTopics() -> [String] { topics }
    func publishedMessages() -> [(topic: String, message: String, tag: Int, ttl: Int)] { messages }
}

private struct FixtureSocialEnvelopeCipher: SocialEnvelopeCiphering {
    let envelope: SocialEventEnvelope

    func seal(_ envelope: SocialEventEnvelope) throws -> String {
        "sealed:" + envelope.id.uuidString
    }

    func open(_ message: String) throws -> SocialEventEnvelope {
        guard message == "sealed:" + envelope.id.uuidString else {
            throw FixtureCipherError.badPayload
        }
        return envelope
    }
}

private enum FixtureCipherError: Error {
    case badPayload
}
