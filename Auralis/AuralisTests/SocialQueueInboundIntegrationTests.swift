@testable import Auralis
import Foundation
import SocialCore
import Testing

@Suite("Social queue — inbound pump drives playlist reconcile")
struct SocialQueueInboundIntegrationTests {
    private func enabledConfiguration() -> SocialFeatureConfiguration {
        SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true])
    }

    /// This test used to be named "A peer's accepted-queue event over the relay reconciles the
    /// linked playlist", and it did not test that.
    ///
    /// Its `authorParticipantID` was `"eip155:1:0xhost"` — the *same id* as the owner record the
    /// fixture mints locally two lines earlier — so the "peer" was a relay envelope claiming this
    /// installation's own author. That shape is now refused as `.impersonatedAuthor`, and refusing
    /// it costs no real functionality: a genuine peer's record is `.pending` on this device,
    /// because a wire `.verified` claim is downgraded (the envelope cannot prove a wallet signed
    /// the join challenge), so a genuine peer's binding events were *already* refused as
    /// `.unverifiedAuthor` long before that guard existed. The feature the old name described has
    /// never worked in production; only the fixture made it look like it did.
    ///
    /// So the honest subject is the wiring — transport → cipher → `handleInbound` → `appendInbound`
    /// → `onProcessed` → `reconcile` — plus the trust boundary that sits in the middle of it. Both
    /// are asserted below. Making a peer's queue mutation actually land needs the transported join
    /// proof described on `SocialSessionProjection.downgradedVerification(of:isLocallyMinted:)`;
    /// until then a positive assertion here would be asserting a fiction.
    @Test("An inbound relay envelope is pumped and processed, but a wire-authored queue mutation does not move the playlist")
    func inboundQueueEventIsProcessedButNotBinding() async throws {
        let store = SocialEventLogStore()
        let sessionID = UUID()
        let invite = SocialInviteMint.mint(sessionID: sessionID, inviterParticipantID: "host")
        let cipher = try SocialEnvelopeCipher(
            base64EncodedSessionKey: invite.encryptedSessionKey,
            sessionID: invite.sessionID,
            relayTopic: invite.relayTopic
        )

        // A verified participant already known to the projection, so their queue mutation is
        // binding. Appended locally because that is the only way an installation holds a
        // `.verified` peer: a relay-delivered claim is downgraded to `.pending` since the envelope
        // cannot prove a wallet signed the join challenge. The *mutation* below still arrives over
        // the relay, which is what this test is actually about.
        let author = "eip155:1:0xhost"
        let identity = SocialParticipantIdentity(
            participantID: author, caip10Account: author, displayName: "Host",
            role: .owner, verificationState: .verified
        )
        await store.appendLocal(SocialEventEnvelope(
            sessionID: sessionID, authorParticipantID: author, createdAt: Date(timeIntervalSince1970: 10),
            event: .participantJoined(identity)
        ))

        let target = InMemoryQueueTarget()
        let queueCoordinator = SocialQueueCoordinator(eventLogStore: store, sessionID: sessionID, playlistTarget: target)

        let coordinator = SocialRelayCoordinator(
            configuration: enabledConfiguration(),
            eventLogStore: store,
            transport: NoopTransport(),
            cipher: cipher,
            boundSessionID: sessionID,
            boundTopic: invite.relayTopic
        )
        let source = ControllableInboundSource()
        let pump = SocialRelayInboundPump(
            coordinator: coordinator,
            source: source,
            onProcessed: { try? await queueCoordinator.reconcile() }
        )
        await pump.start()

        // Sealed with the session key — which every invite holder has, and which proves invite
        // possession rather than authorship — and authored as `author`, i.e. this installation's
        // own locally-minted owner.
        let queueEvent = SocialEventEnvelope(
            sessionID: sessionID, authorParticipantID: author, authorCAIP10Account: author,
            createdAt: Date(timeIntervalSince1970: 20),
            event: .queueMutationAccepted(.acceptProposal(
                proposalID: UUID(),
                item: SocialQueueItem(mediaItemID: "track1", title: "Track 1")
            ))
        )
        // A genuine peer introducing itself. Non-binding, self-authored, and a record this
        // installation does not hold — so the projection accepts it, and it proves the whole pump is
        // wired: transport → cipher.open → handleInbound → appendInbound → durable log. Keeping a
        // positive assertion matters, because asserting only a refusal would also pass if the pump
        // were silently broken.
        let peerJoin = SocialEventEnvelope(
            sessionID: sessionID, authorParticipantID: "eip155:1:0xpeer",
            authorCAIP10Account: "eip155:1:0xpeer",
            createdAt: Date(timeIntervalSince1970: 15),
            event: .participantJoined(SocialParticipantIdentity(
                participantID: "eip155:1:0xpeer", caip10Account: "eip155:1:0xpeer",
                displayName: "Peer", role: .collaborator, verificationState: .pending
            ))
        )
        source.push(topic: invite.relayTopic, message: try cipher.seal(peerJoin))
        #expect(await eventually { await store.allEnvelopes().contains { $0.id == peerJoin.id } })

        source.push(topic: invite.relayTopic, message: try cipher.seal(queueEvent))

        // The impersonation is refused at the boundary: `handleInbound` records the rejection and
        // returns *without* appending, so it never reaches the log and the linked playlist is
        // untouched. If this ever starts returning `["track1"]`, an invite holder can rewrite the
        // user's real playlist by typing the host's participant id into an envelope — that is the
        // whole attack.
        #expect(await target.snapshot().isEmpty)
        #expect(await store.allEnvelopes().contains { $0.id == queueEvent.id } == false)
        await pump.stop()
    }

    private func eventually(timeout: Int = 200, _ predicate: @Sendable () async -> Bool) async -> Bool {
        for _ in 0..<timeout {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await predicate()
    }
}

private actor NoopTransport: SocialRelayTransporting {
    func subscribe(topic: String) async throws { }
    func publish(topic: String, message: String, tag: Int, ttl: Int) async throws { }
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

private actor InMemoryQueueTarget: SocialQueuePlaylistTarget {
    private var items: [String]

    init(_ items: [String] = []) { self.items = items }

    func currentMediaItemIDs() -> [String] { items }
    func add(mediaItemID: String) { items.append(mediaItemID) }
    func remove(mediaItemID: String) { items.removeAll { $0 == mediaItemID } }
    func move(fromPosition: Int, toPosition: Int) {
        guard items.indices.contains(fromPosition) else { return }
        let moved = items.remove(at: fromPosition)
        items.insert(moved, at: min(max(0, toPosition), items.count))
    }

    func snapshot() -> [String] { items }
}
