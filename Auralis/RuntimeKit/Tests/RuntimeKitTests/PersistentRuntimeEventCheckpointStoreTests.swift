import Foundation
import AuralisRuntime
@testable import RuntimeKit
import Testing

@Suite("Persistent runtime event checkpoints")
struct PersistentEventCheckpointStoreTests {
    /// A private `UserDefaults` suite name, so these tests never touch `.standard` and cannot
    /// observe each other's cursors.
    ///
    /// The *name* is what gets shared rather than a `UserDefaults` instance: the store is an actor
    /// and `UserDefaults` is not `Sendable`, so each store is handed its own freshly-made instance —
    /// which is also the more faithful stand-in for reading the cursor back in a later launch.
    private func makeSuiteName() -> String {
        "runtime-event-checkpoint-tests-\(UUID().uuidString)"
    }

    private func makeStore(
        suiteName: String,
        flushInterval: TimeInterval = 5,
        flushEverySaveCount: Int = 32
    ) throws -> PersistentRuntimeEventCheckpointStore {
        PersistentRuntimeEventCheckpointStore(
            defaults: try #require(UserDefaults(suiteName: suiteName)),
            storageKey: "checkpoints",
            flushInterval: flushInterval,
            flushEverySaveCount: flushEverySaveCount
        )
    }

    @Test
    func checkpointSurvivesStoreRecreation() async throws {
        let suiteName = makeSuiteName()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let eventID = UUID()

        let first = try makeStore(suiteName: suiteName)
        await first.saveCheckpoint(eventID, for: "runtime.receipts")
        let recreated = try makeStore(suiteName: suiteName)

        #expect(await recreated.checkpoint(for: "runtime.receipts") == eventID)
    }

    /// The reason this store exists: a burst of saves must not become a burst of plist writes. With
    /// a long interval and a high count threshold only the *first* save of the session is durable —
    /// that one always flushes, because `lastFlush` starts at `.distantPast`.
    @Test
    func savesWithinTheFlushIntervalAreCoalescedRatherThanWrittenThrough() async throws {
        let suiteName = makeSuiteName()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let first = UUID()
        let second = UUID()

        let store = try makeStore(suiteName: suiteName, flushInterval: 600, flushEverySaveCount: 1_000)
        await store.saveCheckpoint(first, for: "runtime.receipts")
        await store.saveCheckpoint(second, for: "runtime.receipts")

        // The in-memory cursor is current...
        #expect(await store.checkpoint(for: "runtime.receipts") == second)
        // ...while the durable one still holds the last flushed value.
        let beforeFlush = try makeStore(suiteName: suiteName)
        #expect(await beforeFlush.checkpoint(for: "runtime.receipts") == first)
    }

    /// `flush()` is the "make it durable now" hook — backgrounding, for instance.
    @Test
    func explicitFlushMakesACoalescedCursorDurable() async throws {
        let suiteName = makeSuiteName()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let latest = UUID()

        let store = try makeStore(suiteName: suiteName, flushInterval: 600, flushEverySaveCount: 1_000)
        await store.saveCheckpoint(UUID(), for: "runtime.receipts")
        await store.saveCheckpoint(latest, for: "runtime.receipts")
        await store.flush()

        let recreated = try makeStore(suiteName: suiteName)
        #expect(await recreated.checkpoint(for: "runtime.receipts") == latest)
    }

    /// The count threshold bounds how much replay an unflushed crash can cost independently of the
    /// clock, so a fast burst inside a single flush interval still reaches disk.
    @Test
    func theSaveCountThresholdForcesAFlushBeforeTheIntervalElapses() async throws {
        let suiteName = makeSuiteName()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let third = UUID()

        let store = try makeStore(suiteName: suiteName, flushInterval: 600, flushEverySaveCount: 2)
        // The first save flushes immediately and resets the counter; the next two hit the threshold.
        await store.saveCheckpoint(UUID(), for: "runtime.receipts")
        await store.saveCheckpoint(UUID(), for: "runtime.receipts")
        await store.saveCheckpoint(third, for: "runtime.receipts")

        let recreated = try makeStore(suiteName: suiteName)
        #expect(await recreated.checkpoint(for: "runtime.receipts") == third)
    }

    /// A cursor saved as the stream goes quiet has to land without another save to carry it, or the
    /// last event of every burst would sit in memory indefinitely.
    @Test
    func theDeferredFlushLandsAfterTheStreamGoesQuiet() async throws {
        let suiteName = makeSuiteName()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let latest = UUID()

        let store = try makeStore(suiteName: suiteName, flushInterval: 0.2, flushEverySaveCount: 1_000)
        await store.saveCheckpoint(UUID(), for: "runtime.receipts")
        await store.saveCheckpoint(latest, for: "runtime.receipts")

        // No further saves: only the scheduled flush can make this durable.
        try await Task.sleep(for: .seconds(1.5))

        let recreated = try makeStore(suiteName: suiteName)
        #expect(await recreated.checkpoint(for: "runtime.receipts") == latest)
    }

    @Test
    func resetClearsBothTheCachedAndTheDurableCursor() async throws {
        let suiteName = makeSuiteName()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let store = try makeStore(suiteName: suiteName)
        await store.saveCheckpoint(UUID(), for: "runtime.receipts")
        await store.resetAll()

        #expect(await store.checkpoint(for: "runtime.receipts") == nil)
        let recreated = try makeStore(suiteName: suiteName)
        #expect(await recreated.checkpoint(for: "runtime.receipts") == nil)
    }
}
