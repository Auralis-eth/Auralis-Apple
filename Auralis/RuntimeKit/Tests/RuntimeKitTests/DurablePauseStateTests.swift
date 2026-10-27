import ArtifactCore
import AuralisPrimaryModels
import Foundation
import ReceiptsCore
import AuralisRuntime
@testable import RuntimeKit
import Testing

private actor PauseLedger: ReceiptStore {
    private var records: [ReceiptRecord] = []

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let record = ReceiptRecord(
            id: UUID(), sequenceID: records.count + 1, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
        records.insert(record, at: 0)
        return record
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] { Array(records.prefix(limit)) }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        Array(records.filter { $0.correlationID == correlationID }.prefix(limit))
    }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { records.removeAll() }

    func pauseReceiptCount() -> Int { records.filter { $0.details.values["paused"] != nil }.count }
}

/// A spy pause store, standing in for `UserDefaults` across a simulated relaunch.
private actor RecordingPauseStore: RuntimePauseStateStoring {
    private var state: RuntimePauseState?
    private(set) var saveCount = 0

    init(initial: RuntimePauseState? = nil) {
        state = initial
    }

    func load() async -> RuntimePauseState? { state }

    func save(_ newState: RuntimePauseState) async {
        state = newState
        saveCount += 1
    }

    func current() -> RuntimePauseState? { state }
}

/// Never yields a readable payload, mirroring a corrupt `UserDefaults` blob.
private struct UnreadablePauseStore: RuntimePauseStateStoring {
    func load() async -> RuntimePauseState? {
        RuntimePauseState(isPaused: true, reason: "The saved pause state could not be read.")
    }
    func save(_ state: RuntimePauseState) async { }
}

/// The global kill switch has to outlive the host that set it.
///
/// `isPaused` was process memory only. Terminating the app resumed operator activity, and — because
/// `RuntimeBackgroundScheduler.runInBackground()` builds its own `ModelContainer` while
/// `RuntimeAssembly` keys its host cache on container identity — a background refresh got a *second*
/// host with its own open `PauseGate`, so due routines fired underneath a person who had paused.
@Suite("Durable pause state")
@MainActor
struct DurablePauseStateTests {
    @Test("an operator pause is written through to the pause store")
    func operatorPauseIsPersisted() async {
        let store = RecordingPauseStore()
        let host = RuntimeHost(
            receiptStore: PauseLedger(),
            governance: RuntimeGovernanceOptions(pauseStateStore: store)
        )
        await host.bootstrap()

        await host.setPaused(true, reason: "Paused for review")

        let saved = await store.current()
        #expect(saved?.isPaused == true)
        #expect(saved?.reason == "Paused for review")
    }

    @Test("a resume is written through too, so the pause does not come back")
    func resumeIsPersisted() async {
        let store = RecordingPauseStore(initial: RuntimePauseState(isPaused: true, reason: "Paused earlier"))
        let host = RuntimeHost(
            receiptStore: PauseLedger(),
            governance: RuntimeGovernanceOptions(pauseStateStore: store)
        )
        await host.bootstrap()
        #expect(host.isPaused)

        await host.setPaused(false)

        #expect(host.isPaused == false)
        #expect(await store.current()?.isPaused == false)
    }

    /// A resume must not be swallowed by a rehydration that has not happened yet.
    ///
    /// `setPaused` was the one governed entry point that did not `bootstrap()`, so a resume arriving
    /// first found `requestedPause` still `false`, took no flip — and rehydration then paused the
    /// host anyway. A person pressed resume and stayed paused, with nothing saying why.
    @Test("a resume with no explicit bootstrap is not swallowed by rehydration")
    func resumeBeforeBootstrapIsHonoured() async {
        let store = RecordingPauseStore(initial: RuntimePauseState(isPaused: true, reason: "Paused earlier"))
        let host = RuntimeHost(
            receiptStore: PauseLedger(),
            governance: RuntimeGovernanceOptions(pauseStateStore: store)
        )

        // Deliberately no `await host.bootstrap()`: the resume is the first thing to touch the host.
        await host.setPaused(false)

        #expect(host.isPaused == false)
        #expect(await store.current()?.isPaused == false, "the resume must be written through")
        #expect(await host.pauseGate.isPaused() == false, "the gate must be open, not just the flag clear")

        // The user-visible end state, and what the old behaviour got wrong: the durable pause is
        // cleared, so the *next* host over the same store does not bring it back.
        let next = RuntimeHost(
            receiptStore: PauseLedger(),
            governance: RuntimeGovernanceOptions(pauseStateStore: store)
        )
        await next.bootstrap()
        #expect(next.isPaused == false, "the resume must have survived, not been swallowed")
    }

    /// The relaunch case: a fresh host reading the same store starts paused, with the reason intact
    /// and the pipeline's gate actually closed — not merely the observable flag set.
    @Test("a new host over the same store starts paused with its gate closed")
    func pauseSurvivesAcrossHosts() async {
        let store = RecordingPauseStore()
        let first = RuntimeHost(
            receiptStore: PauseLedger(),
            governance: RuntimeGovernanceOptions(pauseStateStore: store)
        )
        await first.bootstrap()
        await first.setPaused(true, reason: "Paused by the operator from Mission Control.")

        // A second host over the same durable state — the background refresh's situation exactly.
        let second = RuntimeHost(
            receiptStore: PauseLedger(),
            governance: RuntimeGovernanceOptions(pauseStateStore: store)
        )
        #expect(second.isPaused == false, "not yet rehydrated: the store is read in bootstrap()")

        await second.bootstrap()

        #expect(second.isPaused)
        #expect(second.pauseReason == "Paused by the operator from Mission Control.")
        #expect(await second.pauseGate.isPaused(), "the gate must be closed, not just the flag set")
    }

    /// The whole point: a background scan over a rehydrated host must refuse to run work.
    @Test("a rehydrated pause stops the background routine scan")
    func rehydratedPauseStopsTheScan() async throws {
        let store = RecordingPauseStore(initial: RuntimePauseState(isPaused: true, reason: "Paused"))
        let ledger = PauseLedger()
        let host = RuntimeHost(
            receiptStore: ledger,
            governance: RuntimeGovernanceOptions(pauseStateStore: store)
        )

        // Straight into the scan with no explicit bootstrap, as the background scheduler does.
        await host.runDueRoutines(now: .now, staleSignal: true, approvalPendingSignal: true)

        #expect(host.isPaused)
        // A paused scheduling engine short-circuits each run to a recorded `.noOp` rather than
        // skipping it silently, so the assertion is about the *outcome*, not the absence of a
        // receipt: the scan must have performed no work and claimed no success.
        let records = try await ledger.latest(limit: 200)
        let routineReceipts = records.filter { $0.summary.hasPrefix("Routine ") }
        #expect(routineReceipts.isEmpty == false, "the scan should still record what it weighed")
        #expect(
            routineReceipts.allSatisfy { $0.summary.hasSuffix("noOp") && $0.isSuccess == false },
            "a paused runtime must do no work: \(routineReceipts.map(\.summary))"
        )
    }

    /// Remaining paused is not a new governance act, so rehydration must not receipt one. The flip
    /// that caused it is already in the ledger; a receipt per launch would record a decision nobody
    /// made — the same reasoning `enqueuePauseFlip` applies to a host that starts paused.
    @Test("rehydration writes no pause receipt")
    func rehydrationIsNotReceipted() async {
        let ledger = PauseLedger()
        let host = RuntimeHost(
            receiptStore: ledger,
            governance: RuntimeGovernanceOptions(
                pauseStateStore: RecordingPauseStore(initial: RuntimePauseState(isPaused: true, reason: "Paused"))
            )
        )

        await host.bootstrap()

        #expect(host.isPaused)
        #expect(await ledger.pauseReceiptCount() == 0)
    }

    /// A stale `isPaused: false` must never lift a pause this launch derived for itself — the
    /// storage-unavailable host is paused because its artifact writes would fail, and a previous
    /// healthy launch's "not paused" says nothing about that.
    @Test("a stored resume does not lift a launch-time pause")
    func storedResumeDoesNotLiftAStoragePause() async {
        let host = RuntimeHost(
            receiptStore: PauseLedger(),
            governance: RuntimeGovernanceOptions(
                initialPauseReason: "Operator runtime storage is unavailable.",
                pauseStateStore: RecordingPauseStore(initial: RuntimePauseState(isPaused: false))
            )
        )

        await host.bootstrap()

        #expect(host.isPaused)
        #expect(host.pauseReason == "Operator runtime storage is unavailable.")
    }

    /// A governance-integrity pause is re-derived from registration on every launch, so it must not
    /// be persisted — otherwise a transient registration fault would report itself on a later launch
    /// that registered cleanly.
    @Test("a governance-integrity pause is not persisted")
    func integrityPauseIsNotPersisted() async {
        let store = RecordingPauseStore()
        let host = RuntimeHost(
            receiptStore: PauseLedger(),
            governance: RuntimeGovernanceOptions(pauseStateStore: store)
        )
        host.injectedBootstrapViolations = ["duplicate tool ID: policy.signMessage"]

        await host.bootstrap()

        #expect(host.isPaused)
        #expect(host.bootstrapFailureReason != nil)
        #expect(await store.current() == nil, "the integrity pause must not be written through")
        #expect(await store.saveCount == 0)
    }

    /// An unreadable payload resolves to paused. A kill switch whose state cannot be read must not
    /// default to open.
    @Test("an unreadable pause payload fails closed")
    func unreadablePayloadFailsClosed() async {
        let host = RuntimeHost(
            receiptStore: PauseLedger(),
            governance: RuntimeGovernanceOptions(pauseStateStore: UnreadablePauseStore())
        )

        await host.bootstrap()

        #expect(host.isPaused)
        #expect(host.pauseReason?.isEmpty == false)
    }

    /// With no store — the default, used by tests and previews — behaviour is exactly as before.
    @Test("no pause store leaves the host process-local")
    func noStoreKeepsTheOldBehaviour() async {
        let host = RuntimeHost(receiptStore: PauseLedger())
        await host.bootstrap()
        #expect(host.isPaused == false)

        await host.setPaused(true)
        #expect(host.isPaused)

        let fresh = RuntimeHost(receiptStore: PauseLedger())
        await fresh.bootstrap()
        #expect(fresh.isPaused == false)
    }
}

/// The concrete `UserDefaults` store, as opposed to the doubles above.
///
/// `UnreadablePauseStore` asserts what the *host* does when handed an unreadable-and-therefore-paused
/// state, which presupposes the mapping this suite is about: a payload that cannot be decoded must
/// resolve to `isPaused: true`. That mapping lives only in
/// ``UserDefaultsRuntimePauseStateStore/load()`` and had no test — so the kill switch's own backing
/// was the one `UserDefaults` store in the package with no direct coverage, while the three
/// coordination quarantines and the checkpoint store all had theirs. A regression here fails *open*,
/// which is the one direction a safety control must not fail in, and every test above would still
/// have passed.
@Suite("Durable pause state backing")
struct UserDefaultsRuntimePauseStateStoreTests {
    /// A private suite name so these never touch `.standard`. The name rather than the instance is
    /// what gets shared, because `UserDefaults` is not `Sendable` and the store is an actor.
    private func suiteName(_ label: String) -> String {
        "com.auralis.tests.pauseState.\(label).\(UUID().uuidString)"
    }

    /// Writes raw bytes to the suite, and builds a store over it, without the non-`Sendable`
    /// `UserDefaults` ever crossing an isolation boundary: each handle is created and consumed inside
    /// one `nonisolated` call. Needed because one test below is `@MainActor` (it drives a
    /// ``RuntimeHost``), and handing an actor initializer a `UserDefaults` from actor-isolated code is
    /// exactly the send the concurrency checker refuses.
    private nonisolated static func seed(_ data: Data, key: String, inSuite suiteName: String) {
        UserDefaults(suiteName: suiteName)?.set(data, forKey: key)
    }

    private nonisolated static func makeStore(
        key: String,
        inSuite suiteName: String
    ) -> UserDefaultsRuntimePauseStateStore? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        return UserDefaultsRuntimePauseStateStore(defaults: defaults, key: key)
    }

    @Test("a round-trip restores exactly what was saved")
    func roundTripsThroughUserDefaults() async throws {
        let name = suiteName("roundtrip")
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let store = try #require(Self.makeStore(key: "pauseState", inSuite: name))

        await store.save(RuntimePauseState(isPaused: true, reason: "Paused by the operator."))

        // A *second* store over the same suite, which is what a relaunch actually looks like.
        let relaunched = try #require(Self.makeStore(key: "pauseState", inSuite: name))
        let loaded = await relaunched.load()
        #expect(loaded?.isPaused == true)
        #expect(loaded?.reason == "Paused by the operator.")
    }

    @Test("an absent payload reports no stored state rather than a paused one")
    func absentPayloadIsNotAPause() async throws {
        let name = suiteName("absent")
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let store = try #require(Self.makeStore(key: "pauseState", inSuite: name))

        // Nothing saved is not the same as something unreadable: a first launch must come up running.
        #expect(await store.load() == nil)
    }

    /// The fail-*closed* branch. Corrupt bytes must resolve to paused, not to `nil`.
    @Test("an undecodable payload resolves to paused")
    func undecodablePayloadFailsClosed() async throws {
        let name = suiteName("corrupt")
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        Self.seed(Data("not a pause state".utf8), key: "pauseState", inSuite: name)
        let store = try #require(Self.makeStore(key: "pauseState", inSuite: name))

        let loaded = try #require(await store.load())
        #expect(loaded.isPaused)
        // The reason has to be actionable rather than blank, because it is what the paused-state
        // surface shows in place of a reason a person would recognise.
        #expect(loaded.reason?.isEmpty == false)
    }

    /// The end-to-end version: a host over a corrupt payload comes up paused.
    ///
    /// The two halves — the store's mapping and the host's rehydration — were each covered by a test
    /// that stubbed the other. This is the one that would catch them disagreeing.
    @Test("a host over a corrupt payload comes up paused")
    @MainActor
    func hostOverCorruptPayloadStartsPaused() async throws {
        let name = suiteName("host")
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        Self.seed(Data([0x00, 0x01, 0x02]), key: "pauseState", inSuite: name)
        // Bound to a local first: `RuntimeGovernanceOptions.pauseStateStore` is itself optional, so
        // requiring inline reads to the macro as a check that can never fail.
        let store = try #require(Self.makeStore(key: "pauseState", inSuite: name))

        let host = RuntimeHost(
            receiptStore: PauseLedger(),
            governance: RuntimeGovernanceOptions(pauseStateStore: store)
        )
        await host.bootstrap()

        #expect(host.isPaused)
        #expect(host.pauseReason?.isEmpty == false)
    }
}
