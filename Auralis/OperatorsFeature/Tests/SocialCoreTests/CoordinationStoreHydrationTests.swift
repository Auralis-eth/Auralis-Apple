import Foundation
import AuralisRuntime
@testable import SocialCore
import Testing

/// `RitualStore` and `SharedSessionStore` lazily load their durable state on first access, behind an
/// `await`. Both are actors, but actors are *reentrant* across suspension points, so a caller arriving
/// while the cold load is in flight must not be allowed to run against the un-hydrated store: it would
/// both lose its own change (the load's write-back lands on top) and persist a whole-payload rewrite
/// built from pre-load state. Same failure class as F-1 in `ReceiptSignerFactory`.
struct CoordinationStoreHydrationTests {
    // MARK: - RitualStore

    /// Ritual persistence whose `load()` suspends, widening the reentrancy window that exists anyway.
    private actor RitualPersistenceBox {
        private var state: RitualPersistedState
        private var loadCount = 0

        init(state: RitualPersistedState) { self.state = state }

        func load() async -> RitualPersistedState {
            loadCount += 1
            try? await Task.sleep(for: .milliseconds(30))
            return state
        }

        func save(_ state: RitualPersistedState) { self.state = state }
        func result() -> (state: RitualPersistedState, loads: Int) { (state, loadCount) }
    }

    private struct SlowRitualPersistence: RitualStatePersisting {
        let box: RitualPersistenceBox
        func load() async -> RitualPersistedState { await box.load() }
        func save(_ state: RitualPersistedState) async { await box.save(state) }
    }

    private static let ranAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func seededRitualBox() -> RitualPersistenceBox {
        RitualPersistenceBox(
            state: RitualPersistedState(
                enabledIDs: ["ritual.morning-review"],
                lastRuns: ["ritual.morning-review": Self.ranAt]
            )
        )
    }

    /// The consequential half is the *disk*: losing `lastRuns` makes an already-completed scheduled
    /// ritual due again, so it runs a second time and notifies a second time.
    @Test("a toggle racing the cold load keeps both the persisted history and the toggle")
    func toggleDuringHydrationKeepsPersistedState() async {
        let box = seededRitualBox()
        let store = RitualStore(persistence: SlowRitualPersistence(box: box))

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await store.all() }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(5))   // land inside the load window
                await store.setEnabled(id: "ritual.sesh-prep", true)
            }
        }

        let enabled = Set(await store.enabled().map(\.id))
        let lastRun = await store.lastRun(id: "ritual.morning-review")
        let persisted = await box.result()

        #expect(
            enabled == ["ritual.morning-review", "ritual.sesh-prep"],
            "the toggle or the persisted enabled state was lost to the hydration race"
        )
        #expect(lastRun == Self.ranAt, "in-memory lastRuns were discarded by the hydration race")
        #expect(
            persisted.state.lastRuns["ritual.morning-review"] == Self.ranAt,
            "a write from the un-hydrated store erased lastRuns on disk — the ritual would run again"
        )
        #expect(persisted.state.enabledIDs == ["ritual.morning-review", "ritual.sesh-prep"])
    }

    /// `recordRun` is the write the background scheduler makes, so it is the one most likely to race
    /// a foreground read's cold load.
    @Test("a recorded run racing the cold load does not erase other rituals' last-run times")
    func recordRunDuringHydrationKeepsOtherLastRuns() async {
        let box = seededRitualBox()
        let store = RitualStore(persistence: SlowRitualPersistence(box: box))
        let newRun = Date(timeIntervalSince1970: 1_700_001_000)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await store.all() }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(5))
                await store.recordRun(id: "ritual.weekly-reflection", at: newRun)
            }
        }

        let persisted = await box.result()
        #expect(
            persisted.state.lastRuns["ritual.morning-review"] == Self.ranAt,
            "the persisted last-run time of another ritual was erased on disk"
        )
        #expect(persisted.state.lastRuns["ritual.weekly-reflection"] == newRun)
        #expect(await store.lastRun(id: "ritual.weekly-reflection") == newRun)
    }

    @Test("a cold ritual store loads from persistence only once")
    func coldRitualStoreLoadsOnce() async {
        let box = seededRitualBox()
        let store = RitualStore(persistence: SlowRitualPersistence(box: box))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { _ = await store.all() }
            }
        }

        let persisted = await box.result()
        #expect(persisted.loads == 1, "persistence.load() ran \(persisted.loads) times for one cold store")
    }

    /// The privacy reset preserves ritual *structure*, so it must write through hydrated state — and
    /// nothing an in-flight load carried may survive it.
    @Test("resetting run history keeps enabled toggles and erases history on disk")
    func resetRunHistoryPreservesStructure() async {
        let box = seededRitualBox()
        let store = RitualStore(persistence: SlowRitualPersistence(box: box))

        await store.resetRunHistory()

        let persisted = await box.result()
        #expect(persisted.state.lastRuns.isEmpty, "run history survived the reset")
        #expect(
            persisted.state.enabledIDs == ["ritual.morning-review"],
            "the reset erased the user's enabled toggles, which it is documented to preserve"
        )
        #expect(await store.lastRun(id: "ritual.morning-review") == nil)
    }

    // MARK: - SharedSessionStore

    private actor SharedSessionPersistenceBox {
        private var sessions: [SharedSession]
        private var loadCount = 0

        init(sessions: [SharedSession]) { self.sessions = sessions }

        func load() async -> [SharedSession] {
            loadCount += 1
            try? await Task.sleep(for: .milliseconds(30))
            return sessions
        }

        func save(_ sessions: [SharedSession]) { self.sessions = sessions }
        func result() -> (sessions: [SharedSession], loads: Int) { (sessions, loadCount) }
    }

    private struct SlowSharedSessionPersistence: SharedSessionPersisting {
        let box: SharedSessionPersistenceBox
        func load() async -> [SharedSession] { await box.load() }
        func save(_ sessions: [SharedSession]) async { await box.save(sessions) }
    }

    private func session(_ title: String) -> SharedSession {
        SharedSession(
            correlationID: "corr.\(title)",
            title: title,
            createdBy: ActorRef(kind: .human, identifier: "alice")
        )
    }

    @Test("a session created during the cold load does not erase persisted sessions on disk")
    func createDuringHydrationKeepsPersistedSessions() async {
        let existing = session("existing")
        let box = SharedSessionPersistenceBox(sessions: [existing])
        let store = SharedSessionStore(persistence: SlowSharedSessionPersistence(box: box))
        let fresh = session("fresh")

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await store.allSessions() }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(5))
                await store.create(fresh)
            }
        }

        let persisted = await box.result()
        let persistedIDs = Set(persisted.sessions.map(\.id))
        #expect(
            persistedIDs == [existing.id, fresh.id],
            "a write from the un-hydrated store erased the already-persisted session from disk"
        )
        #expect(Set(await store.allSessions().map(\.id)) == [existing.id, fresh.id])
    }

    /// Reset erases activity, so an in-flight load must not merge sessions back in afterwards.
    @Test("resetting while the cold load is in flight does not resurrect sessions")
    func resetDuringHydrationDoesNotResurrectSessions() async {
        let existing = session("existing")
        let box = SharedSessionPersistenceBox(sessions: [existing])
        let store = SharedSessionStore(persistence: SlowSharedSessionPersistence(box: box))

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await store.allSessions() }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(5))
                await store.reset()
            }
        }

        #expect(await store.allSessions().isEmpty, "the erased session came back in memory")
        let persisted = await box.result()
        #expect(persisted.sessions.isEmpty, "the erased session came back on disk")
    }

    // MARK: - Durable write ordering

    /// Hydration is only half of the whole-payload hazard. Both stores `save` the *entire* collection
    /// on every write, so once the store is warm and the read-modify-write is atomic, the remaining
    /// exposure is the order the saves *land* in: an earlier, slower write completing after a later
    /// one restores a payload that predates changes already accepted in memory. Memory stays correct,
    /// so nothing surfaces until relaunch — which is exactly what makes it worth pinning.
    ///
    /// The boxes below are the `ReorderingBox` harness from ``SocialEventLogStoreConcurrencyTests``,
    /// which proves the same hazard for `SocialEventLogStore.commit`: the *first* save is the slowest,
    /// so completion order inverts unless the store chains its writes.

    private actor ReorderingSessionBox {
        private var sessions: [SharedSession] = []
        private var saveIndex = 0
        private var completionOrder: [Int] = []

        func load() -> [SharedSession] { sessions }

        func save(_ value: [SharedSession]) async {
            saveIndex += 1
            let mine = saveIndex
            try? await Task.sleep(for: .milliseconds(mine == 1 ? 120 : 5))
            sessions = value
            completionOrder.append(mine)
        }

        func result() -> (sessions: [SharedSession], completionOrder: [Int]) { (sessions, completionOrder) }
    }

    private struct ReorderingSessionPersistence: SharedSessionPersisting {
        let box: ReorderingSessionBox
        func load() async -> [SharedSession] { await box.load() }
        func save(_ sessions: [SharedSession]) async { await box.save(sessions) }
    }

    /// A session that reaches the device is work a person started; losing it on disk means it is gone
    /// from Mission Control after the next launch, with no trace that it was ever created.
    @Test("shared session writes land in commit order, not completion order")
    func sharedSessionDurableWritesAreOrdered() async {
        let box = ReorderingSessionBox()
        let store = SharedSessionStore(persistence: ReorderingSessionPersistence(box: box))
        _ = await store.allSessions()   // warm, so only write ordering is under test
        let created = (0..<4).map { session("ordered-\($0)") }

        await withTaskGroup(of: Void.self) { group in
            for session in created {
                group.addTask { await store.create(session) }
            }
        }

        let inMemory = Set(await store.allSessions().map(\.id))
        let result = await box.result()
        #expect(inMemory == Set(created.map(\.id)))
        #expect(
            Set(result.sessions.map(\.id)) == Set(created.map(\.id)),
            "disk lost sessions to out-of-order saves — they are gone on relaunch"
        )
        #expect(result.completionOrder == [1, 2, 3, 4], "saves completed out of commit order")
    }

    private actor ReorderingRitualBox {
        private var state = RitualPersistedState()
        private var saveIndex = 0
        private var completionOrder: [Int] = []

        func load() -> RitualPersistedState { state }

        func save(_ value: RitualPersistedState) async {
            saveIndex += 1
            let mine = saveIndex
            try? await Task.sleep(for: .milliseconds(mine == 1 ? 120 : 5))
            state = value
            completionOrder.append(mine)
        }

        func result() -> (state: RitualPersistedState, completionOrder: [Int]) { (state, completionOrder) }
    }

    private struct ReorderingRitualPersistence: RitualStatePersisting {
        let box: ReorderingRitualBox
        func load() async -> RitualPersistedState { await box.load() }
        func save(_ state: RitualPersistedState) async { await box.save(state) }
    }

    /// `completedOccurrenceIDs` is the consequential field: it is the record that a scheduled
    /// occurrence was *already handled*. A lost entry is not a cosmetic gap — `beginRun` consults it
    /// to refuse a duplicate claim, so the occurrence re-fires after relaunch and the person is
    /// notified twice for one scheduled run.
    @Test("ritual writes land in commit order, not completion order")
    func ritualDurableWritesAreOrdered() async {
        let box = ReorderingRitualBox()
        let store = RitualStore(persistence: ReorderingRitualPersistence(box: box))
        _ = await store.all()   // warm, so only write ordering is under test
        let occurrences = (0..<4).map {
            RitualOccurrenceID(
                ritualID: "ritual.ordered-\($0)",
                scheduledAt: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval($0))
            )
        }

        await withTaskGroup(of: Void.self) { group in
            for occurrence in occurrences {
                group.addTask {
                    await store.finishRun(id: occurrence.ritualID, occurrenceID: occurrence, completed: true)
                }
            }
        }

        let result = await box.result()
        #expect(
            result.state.completedOccurrenceIDs == Set(occurrences),
            "disk lost handled occurrences to out-of-order saves — they re-fire on relaunch"
        )
        #expect(result.completionOrder == [1, 2, 3, 4], "saves completed out of commit order")
    }

    /// The same ordering hazard on the field the scheduler reads to decide whether a ritual is due.
    @Test("recorded run timestamps land in commit order, not completion order")
    func ritualLastRunWritesAreOrdered() async {
        let box = ReorderingRitualBox()
        let store = RitualStore(persistence: ReorderingRitualPersistence(box: box))
        _ = await store.all()
        let runs = (0..<4).map {
            (id: "ritual.ordered-\($0)", at: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval($0)))
        }

        await withTaskGroup(of: Void.self) { group in
            for run in runs {
                group.addTask { await store.recordRun(id: run.id, at: run.at) }
            }
        }

        let result = await box.result()
        #expect(
            result.state.lastRuns == Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0.at) }),
            "disk lost last-run times to out-of-order saves — those rituals run again on relaunch"
        )
    }
}
