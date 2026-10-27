@testable import Auralis
import Foundation
import AuralisOperators
import Testing

@Suite("Social queue coordinator")
struct SocialQueueCoordinatorTests {
    /// Seeds the store with a verified author and an accepted-proposal event per media id.
    private func seedAcceptedQueue(_ store: SocialEventLogStore, sessionID: UUID, media: [String]) async {
        let author = "eip155:1:0xhost"
        let base = Date(timeIntervalSince1970: 1_000)
        let identity = SocialParticipantIdentity(
            participantID: author, caip10Account: author, displayName: "Host",
            role: .owner, verificationState: .verified
        )
        // `appendLocal`, not `appendInbound`: the membership record has to be one this installation
        // established. A relay-delivered `.verified` claim is downgraded to `.pending` — the
        // envelope cannot prove a wallet signed anything — so seeding the host over the wire would
        // leave an author with no authority to accept queue mutations, and this suite would be
        // asserting reconciliation against an empty projection.
        await store.appendLocal(SocialEventEnvelope(
            sessionID: sessionID, authorParticipantID: author, createdAt: base,
            event: .participantJoined(identity)
        ))
        // And `appendLocal` for the mutations too, for a reason the note above half-stated. These
        // are authored as `author` — the identity minted locally just above — so arriving over the
        // relay they are envelopes claiming this installation's own author, which the projection
        // refuses as `.impersonatedAuthor`. Nothing real is lost: a genuine peer's record is
        // `.pending` here, so a peer's binding events were already refused as `.unverifiedAuthor`.
        // This installation's accepted mutations enter through `appendLocal`/`enqueueOutbound`.
        for (offset, mediaID) in media.enumerated() {
            await store.appendLocal(SocialEventEnvelope(
                sessionID: sessionID, authorParticipantID: author,
                createdAt: base.addingTimeInterval(Double(offset + 1)),
                event: .queueMutationAccepted(.acceptProposal(
                    proposalID: UUID(),
                    item: SocialQueueItem(mediaItemID: mediaID, title: mediaID.uppercased())
                ))
            ))
        }
    }

    @Test("reconcile() syncs the linked playlist to the projected accepted queue")
    func reconcileSyncsPlaylist() async throws {
        let store = SocialEventLogStore()
        let sessionID = UUID()
        await seedAcceptedQueue(store, sessionID: sessionID, media: ["a", "b", "c"])

        let target = InMemoryQueueTarget()
        let coordinator = SocialQueueCoordinator(eventLogStore: store, sessionID: sessionID, playlistTarget: target)
        try await coordinator.reconcile()

        #expect(await target.snapshot() == ["a", "b", "c"])
    }

    @Test("A signal drives a reconcile after new queue events arrive")
    func signalDrivenReconcile() async throws {
        let store = SocialEventLogStore()
        let sessionID = UUID()
        let target = InMemoryQueueTarget()
        let coordinator = SocialQueueCoordinator(eventLogStore: store, sessionID: sessionID, playlistTarget: target)

        let (signals, continuation) = AsyncStream.makeStream(of: Void.self)
        await coordinator.start(on: signals)

        // New queue state lands, then a signal fires: the playlist converges.
        await seedAcceptedQueue(store, sessionID: sessionID, media: ["x", "y"])
        continuation.yield(())

        #expect(await eventually { await target.snapshot() == ["x", "y"] })

        await coordinator.stop()
        continuation.finish()
    }

    private func eventually(timeout: Int = 200, _ predicate: @Sendable () async -> Bool) async -> Bool {
        for _ in 0..<timeout {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await predicate()
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
