import Foundation
@testable import AuralisOperators
import Testing

/// `SocialEventLogStore.mutate` reads the snapshot through `currentSnapshot()`, which lazily loads
/// from persistence behind an `await`. `SocialEventLogStore` is an actor, but actors are *reentrant*
/// across suspension points, so two mutations racing the very first (cold) load can each read the
/// same pre-load snapshot and write back over one another — the same failure class as F-1 in
/// `ReceiptSignerFactory`.
struct SocialEventLogStoreConcurrencyTests {
    /// Persistence whose `load()` suspends, widening the reentrancy window that exists regardless.
    private actor SlowPersistenceBox {
        var snapshot = SocialEventLogSnapshot()
        var loadCount = 0
        func load() async -> SocialEventLogSnapshot {
            loadCount += 1
            try? await Task.sleep(for: .milliseconds(20))
            return snapshot
        }
        func save(_ snapshot: SocialEventLogSnapshot) { self.snapshot = snapshot }
        func counts() -> (loads: Int, envelopes: Int) { (loadCount, snapshot.envelopes.count) }
    }

    private struct SlowPersistence: SocialEventLogPersisting {
        let box: SlowPersistenceBox
        func load() async -> SocialEventLogSnapshot { await box.load() }
        func save(_ snapshot: SocialEventLogSnapshot) async { await box.save(snapshot) }
    }

    private func envelope(_ author: String) -> SocialEventEnvelope {
        SocialEventEnvelope(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            authorParticipantID: author,
            event: .workflowShared("workflow.\(author)")
        )
    }

    @Test("concurrent first appends on a cold store do not drop events")
    func concurrentColdAppendsDoNotLoseEvents() async {
        let box = SlowPersistenceBox()
        let store = SocialEventLogStore(persistence: SlowPersistence(box: box))

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask { await store.appendLocal(self.envelope("author-\(index)")) }
            }
        }

        let inMemory = await store.allEnvelopes().count
        let persisted = await box.counts()
        #expect(inMemory == 8, "in-memory log lost events to the cold-load race")
        #expect(persisted.envelopes == 8, "persisted log lost events to the cold-load race")
    }

    @Test("concurrent first invite saves on a cold store do not drop invites")
    func concurrentColdInviteSavesDoNotLoseInvites() async {
        let box = SlowPersistenceBox()
        let store = SocialEventLogStore(persistence: SlowPersistence(box: box))

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<6 {
                group.addTask {
                    await store.saveInvite(
                        SocialInvite(
                            sessionID: UUID(),
                            relayTopic: "irn:topic\(index)",
                            encryptedSessionKey: "key",
                            inviterParticipantID: "alice",
                            expiresAt: Date(timeIntervalSince1970: 10_000),
                            nonce: "nonce\(index)"
                        )
                    )
                }
            }
        }

        let invites = await store.allInvites().count
        #expect(invites == 6, "invites were lost to the cold-load race")
    }

    /// The cold-load race has a second, worse outcome than dropping one of the racing appends: if a
    /// joining mutation reaches the write-back before the load's result is installed, it rewrites the
    /// whole snapshot from *empty* — erasing every already-persisted envelope, invite, and pending
    /// outbound relay event, i.e. work a person asked to publish.
    @Test("concurrent cold appends do not erase the already-persisted log")
    func concurrentColdAppendsDoNotEraseLoadedState() async {
        let box = SlowPersistenceBox()
        let persisted = envelope("persisted")
        await box.save(
            SocialEventLogSnapshot(envelopes: [persisted], pendingOutboundEventIDs: [persisted.id])
        )
        let store = SocialEventLogStore(persistence: SlowPersistence(box: box))

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask { await store.appendLocal(self.envelope("author-\(index)")) }
            }
        }

        let inMemory = await store.allEnvelopes()
        let pending = await store.pendingOutbound()
        let onDisk = await box.counts()
        #expect(inMemory.count == 9, "in-memory log dropped the persisted envelope or an append")
        #expect(
            pending.contains { $0.id == persisted.id },
            "the pending outbound relay queue was erased by the cold-load race"
        )
        #expect(onDisk.envelopes == 9, "disk lost the persisted envelope to the cold-load race")
    }

    /// The cache should be filled once, not once per racing caller.
    @Test("a cold store loads from persistence only once")
    func coldStoreLoadsOnce() async {
        let box = SlowPersistenceBox()
        let store = SocialEventLogStore(persistence: SlowPersistence(box: box))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { _ = await store.currentSnapshot() }
            }
        }

        let counts = await box.counts()
        #expect(counts.loads == 1, "persistence.load() ran \(counts.loads) times for one cold store")
    }

    /// The privacy-reset counterpart of the cold-load race, and the one `hydrate()` guards against by
    /// re-checking the cache after its `await`: a reset that lands while the first load is in flight
    /// must win, because the state it erased is exactly the state the load is carrying. Without the
    /// re-check the load installs the pre-reset snapshot afterwards and the reset silently undoes
    /// itself, in memory and on disk.
    @Test("resetting while the cold load is in flight does not resurrect the log")
    func resetDuringColdLoadDoesNotResurrectLog() async {
        let box = SlowPersistenceBox()
        let persisted = envelope("persisted")
        await box.save(
            SocialEventLogSnapshot(envelopes: [persisted], pendingOutboundEventIDs: [persisted.id])
        )
        let store = SocialEventLogStore(persistence: SlowPersistence(box: box))

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await store.currentSnapshot() }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(5))
                await store.reset()
            }
        }

        #expect(await store.allEnvelopes().isEmpty, "the erased log came back in memory")
        #expect(await store.pendingOutbound().isEmpty, "the erased outbound queue came back")
        let onDisk = await box.counts()
        #expect(onDisk.envelopes == 0, "the erased log came back on disk")
    }

    // MARK: - Durable write ordering

    /// Persistence whose *first* save is the slowest, inverting completion order.
    private actor ReorderingBox {
        var snapshot = SocialEventLogSnapshot()
        var saveIndex = 0
        var completionOrder: [Int] = []
        func load() -> SocialEventLogSnapshot { snapshot }
        func save(_ value: SocialEventLogSnapshot) async {
            saveIndex += 1
            let mine = saveIndex
            try? await Task.sleep(for: .milliseconds(mine == 1 ? 120 : 5))
            snapshot = value
            completionOrder.append(mine)
        }
        func result() -> (envelopes: Int, completionOrder: [Int]) { (snapshot.envelopes.count, completionOrder) }
    }

    private struct ReorderingPersistence: SocialEventLogPersisting {
        let box: ReorderingBox
        func load() async -> SocialEventLogSnapshot { await box.load() }
        func save(_ snapshot: SocialEventLogSnapshot) async { await box.save(snapshot) }
    }

    /// Every save rewrites the whole snapshot, so if a slower earlier write lands after a faster
    /// later one it resurrects a snapshot that predates events already accepted in memory — and those
    /// events are gone on relaunch even though the in-memory log looked correct.
    @Test("durable writes land in commit order, not completion order")
    func durableWritesAreOrdered() async {
        let box = ReorderingBox()
        let store = SocialEventLogStore(persistence: ReorderingPersistence(box: box))
        _ = await store.currentSnapshot()   // warm, so only write ordering is under test

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<4 {
                group.addTask { await store.appendLocal(self.envelope("ordered-\(index)")) }
            }
        }

        let inMemory = await store.allEnvelopes().count
        let result = await box.result()
        #expect(inMemory == 4)
        #expect(result.envelopes == 4, "disk lost events to out-of-order saves")
        #expect(result.completionOrder == [1, 2, 3, 4], "saves completed out of commit order")
    }
}
