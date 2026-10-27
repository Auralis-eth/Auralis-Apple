@testable import Auralis
import Foundation
import AuralisOperators
import Testing

@Suite("Social queue applier")
struct SocialQueueApplierTests {
    private func queue(_ mediaItemIDs: [String]) -> [SocialQueueItem] {
        mediaItemIDs.map { SocialQueueItem(mediaItemID: $0, title: $0.uppercased()) }
    }

    @Test("Reconciles an empty playlist to the queue order")
    func fillsEmpty() async throws {
        let target = InMemoryQueueTarget()
        try await SocialQueueApplier().apply(queueItems: queue(["a", "b", "c"]), to: target)
        #expect(await target.snapshot() == ["a", "b", "c"])
    }

    @Test("Removes tracks no longer queued and reorders the rest")
    func removesAndReorders() async throws {
        let target = InMemoryQueueTarget(["a", "b", "c"])
        try await SocialQueueApplier().apply(queueItems: queue(["c", "a"]), to: target)
        #expect(await target.snapshot() == ["c", "a"])
    }

    @Test("Adds newly queued tracks")
    func addsNew() async throws {
        let target = InMemoryQueueTarget(["a", "b"])
        try await SocialQueueApplier().apply(queueItems: queue(["a", "b", "c", "d"]), to: target)
        #expect(await target.snapshot() == ["a", "b", "c", "d"])
    }

    @Test("Pure reorder matches the desired order")
    func reorders() async throws {
        let target = InMemoryQueueTarget(["a", "b", "c"])
        try await SocialQueueApplier().apply(queueItems: queue(["c", "b", "a"]), to: target)
        #expect(await target.snapshot() == ["c", "b", "a"])
    }

    @Test("Reconciliation is idempotent and de-duplicates media ids")
    func idempotentAndDeduped() async throws {
        let target = InMemoryQueueTarget(["a", "b"])
        let applier = SocialQueueApplier()
        try await applier.apply(queueItems: queue(["b", "a", "a"]), to: target)
        #expect(await target.snapshot() == ["b", "a"])
        // Applying the same desired state again changes nothing.
        try await applier.apply(queueItems: queue(["b", "a"]), to: target)
        #expect(await target.snapshot() == ["b", "a"])
    }

    /// The *target's* list is de-duplicated too, not only the queue projection.
    ///
    /// The session playlist is an ordinary AuraPlay playlist the user can also edit by hand, so it can
    /// hold the same media id twice. When only `queueItems` was de-duplicated, a duplicated desired row
    /// survived the removal filter and `current.count` stayed above `desired.count` — and the reorder
    /// loop is bounded by `desired.indices`, so nothing could ever delete the extra. The playlist then
    /// diverged from the projection permanently, which the "always converges" contract forbids. The
    /// pre-existing dedupe test only ever duplicated ids on the queue side, so this passed green.
    @Test("Reconciliation converges when the target itself holds a duplicate")
    func convergesWhenTargetHasDuplicate() async throws {
        let target = InMemoryQueueTarget(["a", "b", "a"])
        let applier = SocialQueueApplier()

        try await applier.apply(queueItems: queue(["a", "b"]), to: target)

        #expect(await target.snapshot() == ["a", "b"])
        // Exactly one delete: the id is still wanted, so only the *excess* copy goes. Removing it
        // outright and re-adding would be two writes and would move the track to the end.
        #expect(await target.removeCallCount(for: "a") == 1)
        #expect(await target.removeCallCount(for: "b") == 0)
    }

    /// A duplicate of an id that is *no longer* queued must also converge, and must not ask the
    /// service to delete the same id once per occurrence.
    @Test("Reconciliation removes every copy of a track that left the queue")
    func removesAllCopiesOfDepartedTrack() async throws {
        let target = InMemoryQueueTarget(["a", "gone", "b", "gone"])
        let applier = SocialQueueApplier()

        try await applier.apply(queueItems: queue(["a", "b"]), to: target)

        #expect(await target.snapshot() == ["a", "b"])
        // Two copies, two delete calls — the live service drops one row per call, so a single call
        // would leave a departed track sitting in a shared playlist.
        #expect(await target.removeCallCount(for: "gone") == 2)
    }

    /// Duplicates on both sides at once still land on the projection's order.
    @Test("Reconciliation converges with duplicates on both sides")
    func convergesWithDuplicatesOnBothSides() async throws {
        let target = InMemoryQueueTarget(["b", "b", "a", "c"])
        let applier = SocialQueueApplier()

        try await applier.apply(queueItems: queue(["a", "a", "b"]), to: target)

        #expect(await target.snapshot() == ["a", "b"])
    }

    @Test("Applies the projected accepted queue from the event log")
    func appliesProjectedQueue() async throws {
        let store = SocialEventLogStore()
        let sessionID = UUID()
        let author = "eip155:1:0xhost"
        let base = Date(timeIntervalSince1970: 1_000)

        // A verified participant may author binding queue mutations — and verification has to come
        // from this installation, so the record is appended locally. A relay-delivered `.verified`
        // claim is downgraded to `.pending`, because the envelope cannot prove a wallet signed
        // anything, which would leave this author unable to accept any mutation.
        let identity = SocialParticipantIdentity(
            participantID: author, caip10Account: author, displayName: "Host",
            role: .owner, verificationState: .verified
        )
        await store.appendLocal(SocialEventEnvelope(
            sessionID: sessionID, authorParticipantID: author, createdAt: base,
            event: .participantJoined(identity)
        ))
        // `appendLocal`, not `appendInbound`. These envelopes are authored as `author` — the very
        // identity minted locally just above — so delivering them over the relay makes them
        // relay-delivered envelopes claiming this installation's own author, which the projection
        // now refuses as `.impersonatedAuthor`. That refusal is correct and costs nothing real: a
        // genuine peer's record is `.pending` here (a wire `.verified` claim is downgraded), so a
        // peer's binding events were already refused as `.unverifiedAuthor` before the guard
        // existed. This installation's own accepted mutations enter the log through `appendLocal` /
        // `enqueueOutbound`, so that is how the fixture should populate it — the same correction
        // `MissionControlTests.coordinationLoadDerivesSyncQueueAndRitualSummaryFromSocialEventLog`
        // needed for the same reason.
        for (offset, media) in ["a", "b"].enumerated() {
            await store.appendLocal(SocialEventEnvelope(
                sessionID: sessionID, authorParticipantID: author,
                createdAt: base.addingTimeInterval(Double(offset + 1)),
                event: .queueMutationAccepted(.acceptProposal(
                    proposalID: UUID(),
                    item: SocialQueueItem(mediaItemID: media, title: media.uppercased())
                ))
            ))
        }

        let target = InMemoryQueueTarget()
        try await SocialQueueApplier().applyProjectedQueue(from: store, sessionID: sessionID, to: target)
        #expect(await target.snapshot() == ["a", "b"])
    }
}

private actor InMemoryQueueTarget: SocialQueuePlaylistTarget {
    private var items: [String]
    /// How many times each id was passed to ``remove(mediaItemID:)``, so a test can assert the
    /// applier issues one delete per distinct id rather than one per occurrence.
    private var removeCalls: [String: Int] = [:]

    init(_ items: [String] = []) { self.items = items }

    func currentMediaItemIDs() -> [String] { items }

    func add(mediaItemID: String) { items.append(mediaItemID) }

    /// Mirrors the live adapter, which deletes exactly **one** row per call:
    /// `AuraPlayPlaylistService.remove` resolves `items.first(where:)` and deletes that single item.
    /// This fake used to `removeAll`, which made a broken applier look correct — the applier assumed
    /// one call cleared every copy, so against the real service a duplicated playlist never converged
    /// while the suite stayed green.
    func remove(mediaItemID: String) {
        removeCalls[mediaItemID, default: 0] += 1
        guard let index = items.firstIndex(of: mediaItemID) else { return }
        items.remove(at: index)
    }

    func removeCallCount(for mediaItemID: String) -> Int { removeCalls[mediaItemID] ?? 0 }

    func move(fromPosition: Int, toPosition: Int) {
        guard items.indices.contains(fromPosition) else { return }
        let moved = items.remove(at: fromPosition)
        items.insert(moved, at: min(max(0, toPosition), items.count))
    }

    func snapshot() -> [String] { items }
}
