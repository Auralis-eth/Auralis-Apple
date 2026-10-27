import ArtifactCore
import AccountsCore
import AuralisPrimaryModels
import AutopilotCore
import AuralisFoundation
import Foundation
import OperatorsFeature
import PlannerCore
import ReceiptsCore
import RuntimeCore
@testable import RuntimeKit
import SocialCore
import Testing

/// In-memory receipt store that keeps records newest-first, matching `SwiftDataReceiptStore.latest`.
private actor HardeningReceiptStore: ReceiptStore {
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
}

/// Refuses every append, so a caller's degraded-evidence handling is observable.
private struct AlwaysFailingReceiptStore: ReceiptStore {
    struct PersistenceFailure: Error { }
    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord { throw PersistenceFailure() }
    func latest(limit: Int) async throws -> [ReceiptRecord] { [] }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { }
}

/// Serves a fixed page of already-receipted event IDs, newest-first, and records nothing.
private actor SeededEventReceiptStore: ReceiptStore {
    private var seeded: [ReceiptRecord]
    private(set) var appendedEventIDs: [String] = []

    init(seededEventIDs: [UUID]) {
        // Newest-first, mirroring the real store's sort order.
        seeded = seededEventIDs.enumerated().reversed().map { offset, eventID in
            ReceiptRecord(
                id: UUID(), sequenceID: offset + 1,
                createdAt: Date(timeIntervalSince1970: TimeInterval(offset)),
                actor: .system, actorDetail: nil, authorityDetail: nil, mode: .observe,
                trigger: "runtime", scope: "runtime", summary: "seeded", provenance: "local",
                isSuccess: true, correlationID: nil,
                details: ReceiptPayload(values: ["runtimeEventID": .string(eventID.uuidString)])
            )
        }
    }

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        if case let .string(eventID)? = receipt.details.values["runtimeEventID"] {
            appendedEventIDs.append(eventID)
        }
        return ReceiptRecord(
            id: UUID(), sequenceID: seeded.count + appendedEventIDs.count,
            createdAt: receipt.createdAt, actor: receipt.actor, actorDetail: receipt.actorDetail,
            authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
    }

    func latest(limit: Int) async throws -> [ReceiptRecord] { Array(seeded.prefix(limit)) }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] { [] }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { }
}

@MainActor
@Suite("RuntimeHost hardening")
struct RuntimeHostHardeningTests {
    // MARK: - bootstrap

    /// A `didBootstrap` flag set before the first `await` let a second caller past the guard while
    /// registration was still in flight, so it queried an empty registry and got a spurious
    /// "Unknown operator" block. Both callers must now see the same fully registered catalog.
    @Test("concurrent first callers both observe a fully bootstrapped registry")
    func concurrentBootstrapCallersSeeTheFullRegistry() async {
        let host = RuntimeHost(receiptStore: HardeningReceiptStore())

        async let first = host.registeredTools()
        async let second = host.runOperator(toolID: OperatorCatalog.researchBriefID,
                                            request: OperatorRequest(query: "concurrent bootstrap"))
        let (tools, outcome) = await (first, second)

        #expect(tools.isEmpty == false)
        // The race surfaced precisely as this message; anything else means the registry was populated.
        if case let .blocked(reason) = outcome {
            #expect(reason.contains("Unknown operator") == false)
        }
    }

    @Test("bootstrap runs its registration exactly once across many callers")
    func bootstrapIsIdempotentUnderConcurrency() async {
        let host = RuntimeHost(receiptStore: HardeningReceiptStore())

        async let a: Void = host.bootstrap()
        async let b: Void = host.bootstrap()
        async let c: Void = host.bootstrap()
        async let d: Void = host.bootstrap()
        _ = await (a, b, c, d)

        // A second registration pass would have tripped the conflict preconditions in `bootstrap`.
        #expect(await host.registeredTools().isEmpty == false)
    }

    // MARK: - kill switch

    /// The gate and the scheduling engine used to be updated in detached, unawaited tasks while
    /// `isPaused` flipped synchronously, so Mission Control reported "paused" while governed work
    /// could still start.
    @Test("the pause gate is closed by the time the host reports paused")
    func pauseGateClosesBeforeTheHostReportsPaused() async {
        let host = RuntimeHost(receiptStore: HardeningReceiptStore())
        await host.bootstrap()

        await host.setPaused(true, reason: "Test pause")

        #expect(host.isPaused)
        #expect(await host.pauseGate.isPaused())
        #expect(host.pauseReason == "Test pause")
    }

    @Test("governed work is refused immediately after the pause returns")
    func governedWorkIsRefusedOncePauseReturns() async {
        let host = RuntimeHost(receiptStore: HardeningReceiptStore())
        await host.bootstrap()
        await host.setPaused(true)

        let outcome = await host.runOperator(
            toolID: OperatorCatalog.researchBriefID,
            request: OperatorRequest(query: "should not run")
        )

        guard case .blocked = outcome else {
            Issue.record("A governed run started while the runtime reported itself paused: \(outcome)")
            return
        }
    }

    /// The kill switch has to stop an autopilot goal run, and stop it *before* the model runs.
    ///
    /// `PauseGate` was wired into `makePipeline` and the scheduling engine only, so pausing refused
    /// `runOperator`, `runPolicyAction`, and routines while a goal run consulted neither. A paused
    /// runtime planned on device, performed every read-only and advisory step through real
    /// inference, and recorded `autopilot.step.ran` with `isSuccess: true` — only steps that
    /// happened to map to a governed operator were refused, and then by the pipeline rather than by
    /// anything autopilot itself asked. The probe that found this reported
    /// `isComplete: true` with one step receipt written while the gate was confirmed closed.
    ///
    /// `governedWorkIsRefusedOncePauseReturns` above covers `runOperator` and passed throughout, which
    /// is why the gap survived: the tests asked whether the *mechanism* worked, never which entry
    /// points it was attached to.
    @Test("a paused runtime refuses an autopilot goal before any inference happens")
    func autopilotGoalIsRefusedWhilePaused() async throws {
        let store = HardeningReceiptStore()
        let host = RuntimeHost(receiptStore: store)
        host.autopilotPlannerOverride = DeterministicGoalPlanner()
        host.autopilotStepPerformerOverride = DeterministicAutopilotStepPerformer()
        await host.bootstrap()
        await host.setPaused(true, reason: "Operator pressed the kill switch.")

        let run = await host.runAutopilotGoal("inspect my library", correlationID: "corr-paused-goal")

        // Nothing planned and nothing ran.
        #expect(run.plan.steps.isEmpty)
        #expect(run.result.reports.isEmpty)
        #expect(run.result.isComplete == false)
        // No step or planning receipt was written. This is the assertion that would have caught it:
        // the refusal has to precede inference, not merely block execution.
        let receipts = try await store.latest(limit: 64)
        #expect(receipts.contains { $0.trigger.hasPrefix("autopilot.step") } == false)
        #expect(receipts.contains { $0.trigger == "autopilot.planning.model" } == false)
        // And the refusal is announced, so the Run button is not silently inert.
        let updates = await host.recentEvents(limit: 64).compactMap { envelope -> String? in
            guard case let .executionUpdate(message) = envelope.event else { return nil }
            return message
        }
        #expect(updates.contains { $0.contains("Autopilot refused") })
        #expect(updates.contains { $0.contains("Operator pressed the kill switch.") })
    }

    /// Defence in depth: a pause that lands *after* a run has started stops the remaining steps at
    /// ``JudgeStepAuthorizer``, rather than letting the plan carry on to completion. Pinned through
    /// the authorizer directly, since the host refusal above short-circuits before one is built.
    @Test("the authorizer refuses a step once the gate closes mid-run")
    func authorizerRefusesStepsWhileGateIsClosed() async {
        let gate = PauseGate(paused: false)
        let authorizer = JudgeStepAuthorizer(
            judge: DomainJudge(cryptoMode: .observe),
            pauseGate: gate,
            actor: ActorRef(kind: .workflow, identifier: "planner.test")
        )
        let step = PlanStep(
            capability: .runPlugin,
            kind: .observe,
            title: "Summarize the library",
            rationale: "read-only"
        )
        let goal = PlanningGoal(text: "inspect my library", surface: "corr-mid-run")

        // Open gate: the judge decides on the step's own merits.
        let beforePause = await authorizer.authorize(step, in: goal)
        #expect(beforePause.isRunnable)

        await gate.setPaused(true)
        let afterPause = await authorizer.authorize(step, in: goal)

        #expect(afterPause.isRunnable == false)
        #expect(afterPause.message?.contains("paused") == true)
    }

    @Test("resuming restores both the observable flag and the gate")
    func resumingReopensTheGate() async {
        let host = RuntimeHost(
            receiptStore: HardeningReceiptStore(),
            governance: RuntimeGovernanceOptions(initialPauseReason: "Booted paused")
        )
        await host.bootstrap()

        await host.setPaused(false)

        #expect(host.isPaused == false)
        #expect(host.pauseReason == nil)
        #expect(await host.pauseGate.isPaused() == false)
    }

    /// `requestedPause` de-duplicates repeated flips of the same value but cannot order opposite
    /// ones. Two concurrent flips each awaited the gate and the engine independently, and Swift
    /// actors make no FIFO guarantee, so the three could settle on disagreeing values — a kill
    /// switch reporting "paused" over an open gate. Whichever flip lands last, the gate, the
    /// observable flag, and the reason must describe the same state.
    @Test("concurrent opposing pause flips leave the gate and the observable state in agreement")
    func concurrentOpposingPauseFlipsStayConsistent() async {
        for _ in 0..<32 {
            let host = RuntimeHost(receiptStore: HardeningReceiptStore())
            await host.bootstrap()

            async let pausing: Void = host.setPaused(true, reason: "Concurrent pause")
            async let resuming: Void = host.setPaused(false)
            _ = await (pausing, resuming)

            let gateIsPaused = await host.pauseGate.isPaused()
            #expect(host.isPaused == gateIsPaused)
            #expect((host.pauseReason != nil) == host.isPaused)
        }
    }

    /// The `requestedPause` de-duplication guard returned immediately, without awaiting the flip
    /// already in flight. So the *second* of two concurrent callers was told the pause had taken
    /// hold while the gate could still be open — reintroducing, for that caller, exactly the
    /// property the awaited ordering exists to guarantee.
    @Test("a duplicate concurrent pause request waits for the first flip to be enforced")
    func duplicatePauseRequestAwaitsEnforcement() async {
        for _ in 0..<32 {
            let host = RuntimeHost(receiptStore: HardeningReceiptStore())
            await host.bootstrap()

            async let first: Void = host.setPaused(true, reason: "First")
            async let duplicate: Void = host.setPaused(true, reason: "Duplicate")
            _ = await (first, duplicate)

            // Both calls have returned, so enforcement must be in place for both.
            #expect(host.isPaused)
            #expect(await host.pauseGate.isPaused())
        }
    }

    // MARK: - degraded artifact storage

    /// The backlink from a routine's receipt to its artifact is an *index* write. Losing it must not
    /// be reported as a failed run: the artifact was created, the receipt was appended, and the
    /// receipt carries `artifactID` in its payload, so the association is still recoverable from the
    /// ledger. This mirrors the contract `ReceiptStoreSink` holds for the identical backlink, which
    /// is the reason the routine path swallowed the error in the first place — it just did so
    /// without leaving any trace.
    @Test("a routine whose artifact backlink fails still reports the run it actually completed")
    func routineSurvivesAFailedArtifactBacklink() async throws {
        let receiptStore = HardeningReceiptStore()
        let host = RuntimeHost(
            receiptStore: receiptStore,
            stores: RuntimeHostStores(artifactStore: RoutineLinkFailingArtifactStore())
        )
        await host.bootstrap()

        let record = await host.runRoutine(id: "research.brief")

        // The run itself is unaffected: it succeeded and produced the artifact.
        #expect(record.outcome == .success)
        #expect(record.artifactID != nil)
        // And its receipt still landed, carrying the artifact id the lost index would have pointed at.
        let receipts = try await receiptStore.latest(limit: 64)
        let routineReceipt = try #require(receipts.first { $0.scope == "routine" })
        #expect(routineReceipt.correlationID == record.correlationID)
        let artifactID = try #require(record.artifactID)
        #expect(routineReceipt.details.values["artifactID"] == .string(artifactID.uuidString))
    }

    /// An unreadable artifact store must not be reported as an *empty* one. Returning no stale
    /// signal is the fail-safe direction — a store that cannot be read is not evidence that anything
    /// is stale, and firing a cleanup routine on a guess is worse than not firing it — but the read
    /// failure has to stay distinguishable from a genuinely clean store rather than vanishing.
    @Test("an unreadable artifact store yields no stale signal instead of a fabricated one")
    func routineEventSignalsFailSafeOnAnUnreadableArtifactStore() async {
        let host = RuntimeHost(
            receiptStore: HardeningReceiptStore(),
            stores: RuntimeHostStores(artifactStore: ReadFailingArtifactStore())
        )
        await host.bootstrap()

        let signals = await host.routineEventSignals()

        #expect(signals.artifactStaleAt == nil)
        // The approval half is independent of the artifact store and must still be computed.
        #expect(signals.approvalPendingTooLongAt == nil)
    }

    // MARK: - coordination history retention

    /// `SocialEventLogStore.prune` had exactly one caller — `SocialRelayCoordinator`, behind
    /// `ensureEnabled()` — so with the Social v1 relay flag off nothing pruned at all, while
    /// collaborative ritual runs kept appending to a `UserDefaults` snapshot that is rewritten
    /// whole on every mutation. Bootstrap now prunes regardless of the relay.
    @Test("bootstrap prunes aged-out coordination history without the relay")
    func bootstrapPrunesStaleCoordinationHistory() async {
        let log = SocialEventLogStore()
        let staleInvite = SocialInvite(
            sessionID: UUID(),
            relayTopic: "topic",
            encryptedSessionKey: "key",
            inviterParticipantID: "participant",
            // Well past the seven-day `expiredInviteRetention` default.
            expiresAt: Date().addingTimeInterval(-30 * 24 * 60 * 60),
            nonce: "nonce"
        )
        await log.saveInvite(staleInvite)
        #expect(await log.allInvites().count == 1)

        let host = RuntimeHost(
            receiptStore: HardeningReceiptStore(),
            coordination: RuntimeCoordinationStores(socialEventLogStore: log)
        )
        await host.bootstrap()

        #expect(await log.allInvites().isEmpty)
    }

    /// Retention must not reach anything live: a current invite survives the launch prune.
    @Test("a current invite survives the bootstrap prune")
    func bootstrapKeepsCurrentCoordinationHistory() async {
        let log = SocialEventLogStore()
        await log.saveInvite(
            SocialInvite(
                sessionID: UUID(),
                relayTopic: "topic",
                encryptedSessionKey: "key",
                inviterParticipantID: "participant",
                expiresAt: Date().addingTimeInterval(24 * 60 * 60),
                nonce: "nonce"
            )
        )

        let host = RuntimeHost(
            receiptStore: HardeningReceiptStore(),
            coordination: RuntimeCoordinationStores(socialEventLogStore: log)
        )
        await host.bootstrap()

        #expect(await log.allInvites().count == 1)
    }

    // MARK: - social diagnostics

    /// Every other receipt the host writes stamps the live `cryptoMode`; this one hardcoded
    /// `.observe`, so the mode column misreported the posture the app was actually in.
    @Test("a social diagnostic receipt records the host's real crypto mode")
    func socialDiagnosticCarriesTheHostsCryptoMode() async throws {
        let store = HardeningReceiptStore()
        let host = RuntimeHost(
            receiptStore: store,
            identity: RuntimeIdentityHooks(cryptoModeProvider: { .operate })
        )

        await host.recordSocialDiagnostic(
            kind: "relay.publish.failed",
            reason: "transport unavailable",
            sessionID: UUID()
        )

        let receipt = try #require(await store.latest(limit: 1).first)
        #expect(receipt.mode == .operate)
    }

    /// This append was a `try?` that discarded the error, so a lost diagnostic left no trace at all
    /// — including no trace of the relay fault it was recording.
    @Test("a social diagnostic that cannot be persisted raises the degraded-evidence banner")
    func failedSocialDiagnosticRaisesDegradedEvidence() async {
        let host = RuntimeHost(receiptStore: AlwaysFailingReceiptStore())

        await host.recordSocialDiagnostic(
            kind: "relay.publish.failed",
            reason: "transport unavailable",
            sessionID: UUID()
        )

        #expect(host.receiptPersistenceError != nil)
        #expect(host.missingReceiptCount == 1)
    }

    // MARK: - privacy reset

    /// The three human-coordination stores are `UserDefaults`-backed rather than SwiftData-backed, so
    /// they sat outside both the app reset and the runtime container and survived "delete all local
    /// data" carrying session titles and CAIP-10 wallet accounts.
    @Test("the privacy reset erases shared sessions, the social event log, and ritual run history")
    func resetAllHistoryClearsCoordinationState() async throws {
        let ritual = RitualDefinition(
            id: "ritual.reset", kind: .morningReview, name: "Reset Me", summary: "",
            trigger: .schedule(intervalSeconds: 100), playbookIDs: ["research.brief"], isEnabled: true
        )
        let ritualStore = RitualStore(seed: [ritual])
        let host = RuntimeHost(
            receiptStore: HardeningReceiptStore(),
            coordination: RuntimeCoordinationStores(ritualStore: ritualStore)
        )

        let session = await host.sharedSessionStore.create(
            SharedSession(correlationID: "corr-social-reset", title: "Planning", createdBy: .human)
        )
        await host.socialEventLogStore.enqueueOutbound(
            SocialEventEnvelope(
                sessionID: session.id,
                authorParticipantID: "participant-1",
                authorCAIP10Account: "eip155:1:0x1111111111111111111111111111111111111111",
                event: .sessionCreated(title: session.title, correlationID: session.correlationID)
            )
        )
        await ritualStore.recordRun(id: ritual.id, at: Date())

        #expect(await host.sharedSessionStore.allSessions().isEmpty == false)
        #expect(await host.socialEventLogStore.allEnvelopes().isEmpty == false)
        #expect(await ritualStore.lastRun(id: ritual.id) != nil)

        try await host.resetAllHistory()

        #expect(await host.sharedSessionStore.allSessions().isEmpty)
        #expect(await host.socialEventLogStore.allEnvelopes().isEmpty)
        #expect(await host.socialEventLogStore.pendingOutbound().isEmpty)
        #expect(await ritualStore.lastRun(id: ritual.id) == nil)
        // Ritual *structure* is configuration, not activity, and is deliberately preserved.
        #expect(await ritualStore.ritual(id: ritual.id) != nil)
    }

    /// A pending approval is authority to act *and* a copy of the proposal it was raised for — the
    /// address, amount, and calldata a person is being asked to confirm. Nothing about it is durable,
    /// so this is not about surviving relaunch: a reset performed while the app is running left those
    /// proposals in memory and still executable through `resumeApprovedProposal`, so "delete all
    /// local data" could be followed by resuming an approval raised before it.
    @Test("the privacy reset drops pending approvals along with the leases")
    func resetAllHistoryClearsPendingApprovals() async throws {
        let host = RuntimeHost(
            receiptStore: HardeningReceiptStore(),
            governance: RuntimeGovernanceOptions(
                standardCheckConfiguration: StandardCheckConfiguration(allowedChains: .init([.ethMainnet]))
            ),
            // Assist escalates a crypto action rather than refusing it, which is what puts a real
            // approval into custody for this test to find.
            identity: RuntimeIdentityHooks(cryptoModeProvider: { .assist })
        )
        let outcome = await host.runPolicyAction(
            .signMessage,
            actor: .human,
            payload: .signMessage(
                text: "hello",
                address: "0x0000000000000000000000000000000000000001",
                chainID: "1"
            )
        )
        guard case let .needsApproval(request) = outcome else {
            Issue.record("Assist should escalate a sign-message action; got \(outcome)")
            return
        }
        #expect(await host.approvalRegistry.oldestPendingDate() != nil)

        try await host.resetAllHistory()

        #expect(await host.approvalRegistry.oldestPendingDate() == nil)
        // And the authority is genuinely gone, not merely unlisted: the approval no longer resumes.
        let afterReset = await host.resumeApprovedProposal(request)
        guard case .blocked = afterReset else {
            Issue.record("A dropped approval must not still be resumable; got \(afterReset)")
            return
        }
    }

    // MARK: - degraded audit evidence

    /// Autopilot step receipts were written with `try?`, so a failed write left the step reporting
    /// itself as fully receipted with no evidence and no banner.
    @Test("a failed autopilot step receipt raises the degraded-evidence banner")
    func autopilotStepReceiptFailureIsSurfaced() async {
        let host = RuntimeHost(receiptStore: AlwaysFailingReceiptStore())
        // Pin the deterministic planner so the plan carries no inference telemetry and therefore
        // writes no planning receipt. The step receipts are then the only writes that can fail, so
        // the banner can only come from the path under test.
        host.autopilotPlannerOverride = DeterministicGoalPlanner()
        host.autopilotStepPerformerOverride = DeterministicAutopilotStepPerformer()
        await host.bootstrap()

        let run = await host.runAutopilotGoal("Review the local library", correlationID: "corr-degraded")

        #expect(run.plan.deliberation.telemetry == nil)
        #expect(host.receiptPersistenceError != nil)
    }
}

@Suite("Runtime receipt observer seeding")
struct RuntimeReceiptObserverSeedingTests {
    /// `latest` returns newest-first while the retention cache evicts the earliest *appended*, so
    /// seeding in fetch order kept the oldest IDs and forgot the newest — exactly the ones a replay
    /// after an interrupted checkpoint will redeliver.
    @Test("the newest already-receipted event IDs survive seeding and are not re-receipted")
    func seedingRetainsTheNewestEventIDs() async throws {
        // Deeper than the ledger scan reads (`seedScanLimit`, 512), so the seed is genuinely
        // truncated and the ordering property is what decides which IDs survive. The scan limit is
        // the bound that bites first now — it used to be 10,000, above the 1,024-entry retention
        // cap, so this array was sized against the cap instead.
        let eventIDs = (0..<1_200).map { _ in UUID() }
        let newestEventID = try #require(eventIDs.last)
        let store = SeededEventReceiptStore(seededEventIDs: eventIDs)
        let bus = RuntimeEventBus()
        let observer = RuntimeReceiptObserver(events: { await bus.events() }, store: store, publisher: bus)
        await observer.start()

        // Replay the newest already-receipted event, as a reconnect from a stale checkpoint would.
        await bus.publish(
            WorkflowEventEnvelope(
                id: newestEventID,
                event: .capabilityRevoked(.playlistManagement),
                correlationID: "corr-replay"
            )
        )
        try await Task.sleep(for: .milliseconds(200))

        #expect(await store.appendedEventIDs.contains(newestEventID.uuidString) == false)
        await observer.stop()
    }

    /// The seed read was a bare `try?`, so an unreadable ledger left the dedupe cache empty and
    /// reported nothing anywhere — silently removing the protection the cache exists for. The
    /// observer still has to start (refusing would stop auditing altogether, which is worse), so
    /// the failure has to be visible instead.
    @Test("an unreadable ledger leaves the seed failure recorded rather than silent")
    func seedFailureIsRecordedWhenTheLedgerCannotBeRead() async {
        let bus = RuntimeEventBus()
        let observer = RuntimeReceiptObserver(
            events: { await bus.events() },
            store: ReadFailingReceiptStore(),
            publisher: bus
        )

        await observer.start()

        #expect(await observer.seedFailureReason != nil)
        await observer.stop()
    }

    /// The counterpart: a readable ledger leaves no failure recorded, so the signal above means
    /// what it says.
    @Test("a readable ledger records no seed failure")
    func noSeedFailureIsRecordedOnAHealthyLedger() async {
        let bus = RuntimeEventBus()
        let observer = RuntimeReceiptObserver(
            events: { await bus.events() },
            store: SeededEventReceiptStore(seededEventIDs: [UUID()]),
            publisher: bus
        )

        await observer.start()

        #expect(await observer.seedFailureReason == nil)
        await observer.stop()
    }
}

/// A receipt store whose reads fail, standing in for a container that cannot be opened.
private struct ReadFailingReceiptStore: ReceiptStore {
    struct ReadFailure: LocalizedError {
        var errorDescription: String? { "receipt ledger is unreadable" }
    }

    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord { throw ReadFailure() }
    func latest(limit: Int) async throws -> [ReceiptRecord] { throw ReadFailure() }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        throw ReadFailure()
    }
    func exportAll() async throws -> Data { throw ReadFailure() }
    func resetAll() async throws { }
}

@Suite("Coalesced runtime event checkpoints")
struct CoalescedCheckpointStoreTests {
    @Test("a burst of checkpoints is coalesced but still readable, and flush makes it durable")
    func burstIsCoalescedAndFlushIsDurable() async throws {
        let suiteName = "runtime-checkpoint-coalescing-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        // A separate handle for assertions: the one handed to the actor must not be read back here,
        // or the value crosses an isolation boundary while this scope still holds it.
        let reader = try #require(UserDefaults(suiteName: suiteName))
        let store = PersistentRuntimeEventCheckpointStore(
            defaults: try #require(UserDefaults(suiteName: suiteName)),
            storageKey: "checkpoints",
            // Long enough that only the first save of the burst flushes on its own.
            flushInterval: 600,
            flushEverySaveCount: 1_000
        )

        let first = UUID()
        await store.saveCheckpoint(first, for: "runtime.receipts")
        let last = UUID()
        for _ in 0..<10 {
            await store.saveCheckpoint(UUID(), for: "runtime.receipts")
        }
        await store.saveCheckpoint(last, for: "runtime.receipts")

        // Reads always see the in-memory cursor, flushed or not.
        #expect(await store.checkpoint(for: "runtime.receipts") == last)
        // The coalesced writes have not reached disk yet — only the first save did.
        let onDisk = reader.dictionary(forKey: "checkpoints") as? [String: String]
        #expect(onDisk?["runtime.receipts"] == first.uuidString)

        await store.flush()

        let flushed = reader.dictionary(forKey: "checkpoints") as? [String: String]
        #expect(flushed?["runtime.receipts"] == last.uuidString)
    }

    /// The host has to be able to force durability, or the coalescing has no counterpart at all.
    ///
    /// This is the regression guard for the wiring, not just the store: `flush()` was documented as
    /// the "make it durable now" hook for backgrounding and nothing in the app ever called it, so a
    /// terminated process replayed the tail of whatever burst was in flight. The app now calls
    /// `RuntimeAssembly.flushEventCheckpoints()` on the scene's `.background` transition, which
    /// reaches the store through this method.
    ///
    /// It also pins the shape that made the first attempt at this silently fail: a no-op `flush()`
    /// default in a protocol extension shadows an actor's own isolated implementation at the call
    /// site, so `await store.flush()` compiled, typechecked, and did nothing. Going through
    /// `any RuntimeEventCheckpointStoring` here is what would catch that again.
    @Test("the host forces a coalesced cursor to disk through its own flush")
    func hostFlushReachesTheDurableStore() async throws {
        let suiteName = "runtime-checkpoint-host-flush-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let reader = try #require(UserDefaults(suiteName: suiteName))
        let store = PersistentRuntimeEventCheckpointStore(
            defaults: try #require(UserDefaults(suiteName: suiteName)),
            storageKey: "checkpoints",
            flushInterval: 600,
            flushEverySaveCount: 1_000
        )
        let host = await RuntimeHost(
            receiptStore: HardeningReceiptStore(),
            stores: RuntimeHostStores(eventCheckpointStore: store)
        )

        // First save flushes on its own; the second is the one left coalesced in memory.
        await store.saveCheckpoint(UUID(), for: "runtime.receipts")
        let last = UUID()
        await store.saveCheckpoint(last, for: "runtime.receipts")
        #expect((reader.dictionary(forKey: "checkpoints") as? [String: String])?["runtime.receipts"] != last.uuidString)

        await host.flushEventCheckpoints()

        let flushed = reader.dictionary(forKey: "checkpoints") as? [String: String]
        #expect(flushed?["runtime.receipts"] == last.uuidString)
    }

    @Test("resetAll clears both the cache and the persisted cursors")
    func resetClearsCacheAndDisk() async throws {
        let suiteName = "runtime-checkpoint-reset-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let reader = try #require(UserDefaults(suiteName: suiteName))
        let store = PersistentRuntimeEventCheckpointStore(
            defaults: try #require(UserDefaults(suiteName: suiteName)),
            storageKey: "checkpoints"
        )

        await store.saveCheckpoint(UUID(), for: "runtime.receipts")
        await store.resetAll()

        #expect(await store.checkpoint(for: "runtime.receipts") == nil)
        #expect(reader.dictionary(forKey: "checkpoints") == nil)
    }
}

/// An artifact store whose only failure is the receipt backlink, so a routine run's handling of a
/// lost *index* write is observable apart from a store that is broken outright.
private actor RoutineLinkFailingArtifactStore: ArtifactStore {
    struct LinkFailure: LocalizedError {
        var errorDescription: String? { "artifact index write failed" }
    }

    // See the note on `LinkFailingArtifactStore` in `ReceiptStoreSinkTests`: the in-memory base
    // satisfies these throwing requirements without throwing, so the forwarding calls need no `try`.
    private let base = InMemoryArtifactStore()

    func create(_ draft: ArtifactDraft) async throws -> Artifact { await base.create(draft) }
    func addVersion(toGroup groupID: UUID, _ draft: ArtifactDraft) async throws -> Artifact {
        await base.addVersion(toGroup: groupID, draft)
    }
    func get(id: UUID) async -> Artifact? { await base.get(id: id) }
    func latest(limit: Int) async throws -> [Artifact] { await base.latest(limit: limit) }
    func versions(ofGroup groupID: UUID) async throws -> [Artifact] { await base.versions(ofGroup: groupID) }
    func all(ofType type: ArtifactType, limit: Int) async throws -> [Artifact] {
        await base.all(ofType: type, limit: limit)
    }
    func setApprovalState(id: UUID, to state: ArtifactApprovalState) async throws {
        try await base.setApprovalState(id: id, to: state)
    }
    func linkRelatedReceipt(id receiptID: UUID, toArtifact artifactID: UUID) async throws {
        throw LinkFailure()
    }
    func updateLifecycle(
        id: UUID,
        to state: ArtifactApprovalState,
        destination: String?,
        exportFormat: String?
    ) async throws {
        try await base.updateLifecycle(id: id, to: state, destination: destination, exportFormat: exportFormat)
    }
    // `exportAll` is the one that really can throw — it JSON-encodes — so it keeps its `try`.
    func exportAll() async throws -> Data { try await base.exportAll() }
    func resetAll() async throws { await base.resetAll() }
}

/// An artifact store whose reads fail, standing in for a container that cannot be opened.
private actor ReadFailingArtifactStore: ArtifactStore {
    struct ReadFailure: LocalizedError {
        var errorDescription: String? { "artifact store is unreadable" }
    }

    private let base = InMemoryArtifactStore()

    func create(_ draft: ArtifactDraft) async throws -> Artifact { await base.create(draft) }
    func addVersion(toGroup groupID: UUID, _ draft: ArtifactDraft) async throws -> Artifact {
        await base.addVersion(toGroup: groupID, draft)
    }
    func get(id: UUID) async -> Artifact? { nil }
    func latest(limit: Int) async throws -> [Artifact] { throw ReadFailure() }
    func versions(ofGroup groupID: UUID) async throws -> [Artifact] { throw ReadFailure() }
    func all(ofType type: ArtifactType, limit: Int) async throws -> [Artifact] { throw ReadFailure() }
    func setApprovalState(id: UUID, to state: ArtifactApprovalState) async throws {
        try await base.setApprovalState(id: id, to: state)
    }
    func linkRelatedReceipt(id receiptID: UUID, toArtifact artifactID: UUID) async throws { }
    func updateLifecycle(
        id: UUID,
        to state: ArtifactApprovalState,
        destination: String?,
        exportFormat: String?
    ) async throws { }
    func exportAll() async throws -> Data { throw ReadFailure() }
    func resetAll() async throws { }
}
